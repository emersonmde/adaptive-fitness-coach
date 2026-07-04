import Foundation
import HealthKit
import AdaptiveCore

/// C5 — Apple Health is the system of record for meals; the app is the pen, Health the paper.
/// Entries are `HKCorrelation(.food)` wrapping energy + macro quantity samples, with
/// provenance / source URL / estimate range / quantity carried in metadata so the app's own
/// surfaces reconstruct honest entries **from Health**, not a private store. Deleting the app
/// loses nothing logged.
///
/// This is the phone target's first HealthKit code — the watch's `HealthKitAuthorization` is
/// the pattern, but nothing is shared (different store, different types).
final class HealthKitNutritionRecorder: NutritionRecorder, @unchecked Sendable {

    enum MetadataKey {
        static let entryID = "AFCEntryID"
        static let provenance = "AFCProvenance"       // Provenance.metadataValue
        static let databaseName = "AFCDatabaseName"
        static let sourceURL = "AFCSourceURL"
        static let kcalLow = "AFCKcalLow"             // estimates only (Health has no range type)
        static let kcalHigh = "AFCKcalHigh"
        static let assumptions = "AFCAssumptions"     // "a · b · c"
        static let quantity = "AFCQuantity"           // servings; samples store totals
        static let serving = "AFCServing"
        static let meal = "AFCMeal"                   // MealSlot.rawValue (build 8)
        static let sellerName = "AFCSellerName"       // who sold it (build 11)
        static let sellerDomain = "AFCSellerDomain"
    }

    private let store = HKHealthStore()
    private let observerLock = NSLock()
    private var observerContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var observerQueryStarted = false

    private static let energyType = HKQuantityType(.dietaryEnergyConsumed)
    private static let proteinType = HKQuantityType(.dietaryProtein)
    private static let carbType = HKQuantityType(.dietaryCarbohydrates)
    private static let fatType = HKQuantityType(.dietaryFatTotal)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let foodType = HKCorrelationType(.food)

    private static var allQuantityTypes: Set<HKSampleType> {
        [energyType, proteinType, carbType, fatType]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CocoaError(.featureUnsupported)
        }
        // Share to write; read the same types (+ active energy for the day screen's
        // informational burn line). A user denial is not a throw — HealthKit reports it
        // through the write path (and hides read denial by design; the daily line degrades
        // honestly). The .food CORRELATION type must NOT appear here: correlation types are
        // disallowed in authorization requests and raise NSInvalidArgumentException
        // ("Authorization to read the following types is disallowed") — authorization lives
        // on the contained quantity types; correlation queries need no grant of their own.
        // Source: HKHealthStore.requestAuthorization docs / HKCorrelationType.
        try await store.requestAuthorization(
            toShare: Self.allQuantityTypes,
            // .workoutType() rides along for the hub strip's done-marks (WorkoutWeekHistory)
            // — reads stay deferred-contextual behind the first meal Log rather than adding
            // a second launch-time prompt.
            read: Self.allQuantityTypes.union([Self.activeEnergyType, HKObjectType.workoutType()])
        )
    }

    func record(_ entry: MealEntry) async throws {
        let servings = Double(max(1, entry.quantity))
        var samples: Set<HKSample> = []

        func add(_ type: HKQuantityType, _ unit: HKUnit, _ perServing: Double?) {
            guard let perServing, perServing > 0 else { return }
            samples.insert(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: perServing * servings),
                start: entry.date,
                end: entry.date
            ))
        }
        add(Self.energyType, .kilocalorie(), entry.facts.energy.midpointKcal)
        add(Self.proteinType, .gram(), entry.facts.proteinGrams)
        add(Self.carbType, .gram(), entry.facts.carbGrams)
        add(Self.fatType, .gram(), entry.facts.fatGrams)
        guard !samples.isEmpty else { return }

        var metadata: [String: Any] = [
            HKMetadataKeyFoodType: entry.name,
            MetadataKey.entryID: entry.id.uuidString,
            MetadataKey.provenance: entry.provenance.metadataValue,
            MetadataKey.quantity: entry.quantity,
            MetadataKey.meal: entry.meal.rawValue,
        ]
        if let seller = entry.seller {
            metadata[MetadataKey.sellerName] = seller.name
            if let domain = seller.domainHint {
                metadata[MetadataKey.sellerDomain] = domain
            }
        }
        switch entry.provenance {
        case .verified(let url):
            if let url { metadata[MetadataKey.sourceURL] = url.absoluteString }
        case .database(let name, let url):
            metadata[MetadataKey.databaseName] = name
            if let url { metadata[MetadataKey.sourceURL] = url.absoluteString }
        case .estimate(let assumptions):
            metadata[MetadataKey.assumptions] = assumptions.joined(separator: " · ")
        case .userStated:
            break   // the metadataValue string carries everything
        }
        if case .range(let low, let high) = entry.facts.energy {
            metadata[MetadataKey.kcalLow] = low * servings
            metadata[MetadataKey.kcalHigh] = high * servings
        }
        if let serving = entry.facts.servingDescription {
            metadata[MetadataKey.serving] = serving
        }

        let correlation = HKCorrelation(
            type: Self.foodType,
            start: entry.date,
            end: entry.date,
            objects: samples,
            metadata: metadata
        )
        try await store.save(correlation)
    }

    func delete(entryID: UUID) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: MetadataKey.entryID,
            allowedValues: [entryID.uuidString]
        )
        let correlations: [HKCorrelation] = try await sampleQuery(type: Self.foodType, predicate: predicate)
        for correlation in correlations {
            // Contained samples are not auto-deleted with their correlation.
            let contained = Array(correlation.objects)
            try await store.delete(correlation)
            if !contained.isEmpty {
                try await store.delete(contained)
            }
        }
    }

    func intake(on day: Date) async throws -> DailyIntake {
        let predicate = Self.dayPredicate(day)

        // Total = ALL dietary energy that day, any source (another app's entries still count
        // toward the user's day — we're a pen, not the only pen).
        let energySamples: [HKQuantitySample] = try await sampleQuery(type: Self.energyType, predicate: predicate)
        let total = energySamples.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }

        // Entries = our correlations, reconstructed from metadata.
        let correlations: [HKCorrelation] = try await sampleQuery(type: Self.foodType, predicate: predicate)
        let entries = correlations.compactMap(Self.entry(from:)).sorted { $0.date < $1.date }
        return DailyIntake(totalKcal: total, entries: entries)
    }

    func activeEnergyBurned(on day: Date) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: Self.activeEnergyType,
                quantitySamplePredicate: Self.dayPredicate(day),
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    // Read denial surfaces as an error here; the burn line is informational —
                    // callers treat a throw as "show nothing", never as zero-with-confidence.
                    continuation.resume(throwing: error)
                } else {
                    let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    continuation.resume(returning: kcal)
                }
            }
            store.execute(query)
        }
    }

    private static func dayPredicate(_ day: Date) -> NSPredicate {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
        return HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    }

    /// ONE long-running observer query per process, started lazily, fanned out to every
    /// active stream. Streams end (and unregister) when their consuming `.task` is
    /// cancelled — executing a fresh HKObserverQuery per screen appearance leaked a live
    /// query (HealthKit keeps executed queries alive; `stop` was never called).
    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            observerLock.lock()
            observerContinuations[id] = continuation
            let needsQuery = !observerQueryStarted
            observerQueryStarted = true
            observerLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.observerLock.lock()
                self.observerContinuations[id] = nil
                self.observerLock.unlock()
            }

            if needsQuery {
                let query = HKObserverQuery(sampleType: Self.energyType, predicate: nil) { [weak self] _, completion, _ in
                    guard let self else { completion(); return }
                    self.observerLock.lock()
                    let continuations = Array(self.observerContinuations.values)
                    self.observerLock.unlock()
                    continuations.forEach { $0.yield() }
                    completion()
                }
                store.execute(query)
            }
        }
    }

    // MARK: -

    private static func entry(from correlation: HKCorrelation) -> MealEntry? {
        guard let metadata = correlation.metadata,
              let idString = metadata[MetadataKey.entryID] as? String,
              let id = UUID(uuidString: idString) else {
            return nil   // not ours (no reconstructable metadata)
        }
        let name = (metadata[HKMetadataKeyFoodType] as? String) ?? "Meal"
        let servings = Double(max(1, (metadata[MetadataKey.quantity] as? Int) ?? 1))

        func total(_ type: HKQuantityType, _ unit: HKUnit) -> Double? {
            let samples = correlation.objects(for: type)
            guard !samples.isEmpty else { return nil }
            let sum = samples.compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
                .reduce(0, +)
            return sum / servings   // samples store totals; entries speak per-serving
        }

        let energy: NutritionFacts.Energy
        if let low = metadata[MetadataKey.kcalLow] as? Double,
           let high = metadata[MetadataKey.kcalHigh] as? Double {
            energy = .range(lowKcal: low / servings, highKcal: high / servings)
        } else if let kcal = total(energyType, .kilocalorie()) {
            energy = .exact(kcal: kcal)
        } else {
            return nil
        }

        let sourceURL = (metadata[MetadataKey.sourceURL] as? String).flatMap(URL.init(string:))
        let provenance: Provenance
        switch metadata[MetadataKey.provenance] as? String {
        case "verified":
            provenance = .verified(sourceURL: sourceURL)
        case "estimate":
            let assumptions = (metadata[MetadataKey.assumptions] as? String)?
                .components(separatedBy: " · ") ?? []
            provenance = .estimate(assumptions: assumptions)
        case "userStated":
            provenance = .userStated
        default:
            provenance = .database(
                name: (metadata[MetadataKey.databaseName] as? String) ?? "database",
                sourceURL: sourceURL
            )
        }

        let meal = (metadata[MetadataKey.meal] as? String).flatMap(MealSlot.init(rawValue:))
        let seller = (metadata[MetadataKey.sellerName] as? String).map {
            Seller(name: $0, domainHint: metadata[MetadataKey.sellerDomain] as? String)
        }

        return MealEntry(
            id: id,
            date: correlation.startDate,
            name: name,
            quantity: Int(servings),
            facts: NutritionFacts(
                energy: energy,
                proteinGrams: total(proteinType, .gram()),
                carbGrams: total(carbType, .gram()),
                fatGrams: total(fatType, .gram()),
                servingDescription: metadata[MetadataKey.serving] as? String
            ),
            provenance: provenance,
            meal: meal,   // nil (build-7 entries) → init derives from the entry's time
            seller: seller
        )
    }

    private func sampleQuery<T: HKSample>(type: HKSampleType, predicate: NSPredicate) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [T]) ?? [])
                }
            }
            store.execute(query)
        }
    }
}
