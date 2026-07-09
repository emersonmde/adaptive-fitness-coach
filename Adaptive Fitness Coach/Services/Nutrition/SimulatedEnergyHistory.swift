import Foundation
import AdaptiveCore

/// A deterministic 28-day energy history for `-simulateMealScan`, tuned so the calibration comes
/// out confident and reads "runs ~10% below the textbook estimate" — enough to demo the tuned
/// budget and the calibration note without a real Health store. Matches `FixedBodyProfileSource`
/// (80 kg / 180 cm / 35 / male, Mifflin BMR 1755).
enum SimulatedEnergyHistory {

    static var demo: EnergyHistory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let slopePerDay = -0.0296            // ≈ −0.83 kg over the window (a real deficit)
        let startWeight = 80.0

        var weights: [DatedValue] = []
        var intake: [DatedValue] = []
        var active: [DatedValue] = []
        for i in 0..<28 {
            let date = calendar.date(byAdding: .day, value: -(27 - i), to: today) ?? today
            // Small reversible "water" wobble so the trend fit has something to smooth.
            let wobble = 0.15 * sin(Double(i) * 1.3)
            weights.append(DatedValue(date: date, value: startWeight + slopePerDay * Double(i) + wobble))
            intake.append(DatedValue(date: date, value: 1800))
            active.append(DatedValue(date: date, value: 560 + 30 * sin(Double(i) * 0.7)))
        }
        return EnergyHistory(weights: weights, dailyIntakeKcal: intake, dailyActiveKcal: active)
    }
}
