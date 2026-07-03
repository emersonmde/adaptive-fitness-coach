import Foundation
import HealthKit
import AdaptiveCore

/// Reads the body data the target suggestion needs (Mifflin-St Jeor is sexed and sized) from
/// HealthKit: latest bodyMass + height samples, date-of-birth and biological-sex
/// characteristics. ANY missing piece → `nil` profile and the target sheet falls back to
/// manual entry — HealthKit deliberately hides read denial, so absent data and denied data
/// are indistinguishable and the copy never accuses.
final class HealthKitBodyProfileSource: BodyProfileSource, @unchecked Sendable {

    private let store = HKHealthStore()

    private static let massType = HKQuantityType(.bodyMass)
    private static let heightType = HKQuantityType(.height)

    /// Deferred-contextual: called by the target sheet when it opens (the value of granting
    /// is clearest at that moment), never at app launch.
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        try await store.requestAuthorization(
            toShare: [],
            read: [
                Self.massType,
                Self.heightType,
                HKCharacteristicType(.dateOfBirth),
                HKCharacteristicType(.biologicalSex),
            ]
        )
    }

    func currentProfile() async throws -> BodyProfile? {
        // Characteristics throw when unauthorized/unset — either way, no suggestion.
        guard let dobComponents = try? store.dateOfBirthComponents(),
              let dob = Calendar.current.date(from: dobComponents),
              let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year,
              age > 0
        else { return nil }

        let sex: BodyProfile.Sex
        switch (try? store.biologicalSex())?.biologicalSex {
        case .male: sex = .male
        case .female: sex = .female
        default: return nil   // .notSet / .other / unauthorized — formula needs one; go manual
        }

        guard let massSample = await latestSample(of: Self.massType),
              let heightSample = await latestSample(of: Self.heightType) else {
            return nil
        }
        let massKg = massSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let heightCm = heightSample.quantity.doubleValue(for: .meterUnit(with: .centi))

        guard massKg > 20, heightCm > 90 else { return nil }   // implausible data → manual
        return BodyProfile(massKg: massKg, heightCm: heightCm, ageYears: age, sex: sex)
    }

    private func latestSample(of type: HKQuantityType) async -> HKQuantitySample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }
}

/// Deterministic profile for the simulator/UI tests: a fixed 80 kg / 180 cm / 35-year-old
/// male (BMR 1755 — the same fixture the package tests pin), so the target sheet's suggested
/// numbers are stable.
struct FixedBodyProfileSource: BodyProfileSource {
    var profile: BodyProfile? = BodyProfile(massKg: 80, heightCm: 180, ageYears: 35, sex: .male)

    func currentProfile() async throws -> BodyProfile? { profile }
}
