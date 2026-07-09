import Foundation
import HealthKit
import AdaptiveCore

/// Reads the trailing weight / dietary-energy / active-energy series the TDEE calibration needs.
/// Daily energy totals come from `HKStatisticsCollectionQuery` (day-bucketed cumulative sums);
/// weight is the raw `bodyMass` sample list over the window (the trend fit tolerates the noise).
///
/// All three reads (`.bodyMass`, `.dietaryEnergyConsumed`, `.activeEnergyBurned`) are already
/// granted elsewhere; we re-declare them so this source works even if it authorizes first.
/// Following the house rule: a read denial is indistinguishable from missing data, so we return
/// whatever came back and let the calibrator degrade to the safe prior — never accuse.
final class HealthKitEnergyHistorySource: EnergyHistorySource, @unchecked Sendable {

    private let store = HKHealthStore()

    private static let massType = HKQuantityType(.bodyMass)
    private static let dietaryType = HKQuantityType(.dietaryEnergyConsumed)
    private static let activeType = HKQuantityType(.activeEnergyBurned)

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        try await store.requestAuthorization(
            toShare: [],
            read: [Self.massType, Self.dietaryType, Self.activeType]
        )
    }

    func history(trailingDays days: Int, endingOn day: Date) async throws -> EnergyHistory {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        let start = calendar.date(byAdding: .day, value: -max(1, days), to: calendar.startOfDay(for: day))
            ?? calendar.startOfDay(for: day)

        async let weights = weightSamples(start: start, end: end, calendar: calendar)
        async let intake = dailyTotals(of: Self.dietaryType, start: start, end: end, calendar: calendar)
        async let active = dailyTotals(of: Self.activeType, start: start, end: end, calendar: calendar)

        return EnergyHistory(
            weights: (try? await weights) ?? [],
            dailyIntakeKcal: (try? await intake) ?? [],
            dailyActiveKcal: (try? await active) ?? []
        )
    }

    private func weightSamples(start: Date, end: Date, calendar: Calendar) async throws -> [DatedValue] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: Self.massType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    DatedValue(date: $0.endDate, value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func dailyTotals(of type: HKQuantityType, start: Date, end: Date, calendar: Calendar) async throws -> [DatedValue] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let anchor = calendar.startOfDay(for: start)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [DatedValue] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()), kcal > 0 {
                        values.append(DatedValue(date: stats.startDate, value: kcal))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
}
