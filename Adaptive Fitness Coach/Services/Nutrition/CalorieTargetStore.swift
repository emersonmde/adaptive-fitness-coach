import Foundation
import AdaptiveCore

/// The user's daily calorie target — a *setting*, not food data (C5 untouched: no nutrition
/// ever lives outside Health). UserDefaults-backed, `@Observable` so the gauge and the hub
/// line re-render on change; ephemeral under `-uiTesting` so every UI-test launch starts
/// unset (which also keeps the pre-target daily-line text assertions valid).
@MainActor
@Observable
final class CalorieTargetStore {

    private static let targetKey = "calorieTargetKcal"
    private static let goalKey = "calorieTargetGoal"
    private static let offeredKey = "calorieTargetOffered"

    private let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    private(set) var target: Int?
    private(set) var goal: CalorieGoal?
    /// Whether the first-run sheet was ever shown (offered once, skippable — a target is
    /// opt-in, C6).
    private(set) var wasOffered: Bool

    init() {
        if ephemeral {
            target = nil
            goal = nil
            wasOffered = false
        } else {
            let stored = UserDefaults.standard.integer(forKey: Self.targetKey)
            target = stored > 0 ? stored : nil
            goal = UserDefaults.standard.string(forKey: Self.goalKey).flatMap(CalorieGoal.init(rawValue:))
            wasOffered = UserDefaults.standard.bool(forKey: Self.offeredKey)
        }
    }

    func set(target newTarget: Int, goal newGoal: CalorieGoal?) {
        target = max(0, newTarget) == 0 ? nil : newTarget
        goal = newGoal
        markOffered()
        guard !ephemeral else { return }
        UserDefaults.standard.set(newTarget, forKey: Self.targetKey)
        UserDefaults.standard.set(newGoal?.rawValue, forKey: Self.goalKey)
    }

    func clear() {
        target = nil
        goal = nil
        guard !ephemeral else { return }
        UserDefaults.standard.removeObject(forKey: Self.targetKey)
        UserDefaults.standard.removeObject(forKey: Self.goalKey)
    }

    func markOffered() {
        wasOffered = true
        guard !ephemeral else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
    }

    func budget(consumedKcal: Double) -> DayBudget? {
        guard let target else { return nil }
        return DayBudget(targetKcal: target, consumedKcal: consumedKcal)
    }
}
