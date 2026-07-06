import Foundation
import AdaptiveCore

/// Aggregates recent eating for a context pack's nutrition section: per-day kcal/protein
/// totals plus the sellers that actually recur — patterns, not a raw food log. Reads through
/// the existing `NutritionRecorder` day queries (Health is the record, C5), one day at a
/// time; days with nothing logged are simply absent.
enum NutritionDigestBuilder {
    static func digest(
        recorder: any NutritionRecorder,
        target: Int?,
        days: Int = 30,
        now: Date = Date()
    ) async -> NutritionDigest {
        let calendar = Calendar.current
        var dayRows: [NutritionDigest.Day] = []
        var sellerCounts: [String: Int] = [:]

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            guard let intake = try? await recorder.intake(on: day), intake.totalKcal > 0 else { continue }
            let protein = intake.entries.compactMap(\.facts.proteinGrams).reduce(0, +)
            dayRows.append(NutritionDigest.Day(
                date: calendar.startOfDay(for: day),
                totalKcal: Int(intake.totalKcal.rounded()),
                proteinGrams: protein > 0 ? Int(protein.rounded()) : nil
            ))
            for entry in intake.entries {
                if let seller = entry.seller?.name { sellerCounts[seller, default: 0] += 1 }
            }
        }

        let frequent = sellerCounts
            .filter { $0.value >= 2 }                       // recurring, not one-offs
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)

        return NutritionDigest(days: dayRows, calorieTarget: target, frequentSellers: Array(frequent))
    }
}
