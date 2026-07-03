import Foundation

/// The daily calorie target (build 8) — suggestion math, pure and pinned by tests.
///
/// The whole reason to count calories is a target; the C6 amendment that admits one is
/// deliberate and bounded: a target the user chose is a tool. No red days, no alarms, no
/// streaks — `DayBudget` computes quiet arithmetic and the gauge renders it once.

/// Inputs to the suggestion. All four are required — the formula is sexed and sized; when
/// Health lacks any piece the app falls back to manual entry, never a silent constant.
public struct BodyProfile: Sendable, Equatable {
    public enum Sex: Sendable, Equatable {
        case male
        case female
    }

    public var massKg: Double
    public var heightCm: Double
    public var ageYears: Int
    public var sex: Sex

    public init(massKg: Double, heightCm: Double, ageYears: Int, sex: Sex) {
        self.massKg = massKg
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
    }
}

/// Standard TDEE activity multipliers (sedentary→active).
public enum ActivityLevel: String, Sendable, CaseIterable, Codable {
    case sedentary
    case light
    case moderate
    case active

    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        }
    }

    public var displayName: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Lightly active"
        case .moderate: "Active most days"
        case .active: "Very active"
        }
    }
}

public enum CalorieGoal: String, Sendable, CaseIterable, Codable {
    case lose       // ≈ −500 kcal/day ≈ 1 lb/week
    case maintain
    case gain       // ≈ +500 kcal/day

    public var deltaKcal: Double {
        switch self {
        case .lose: -500
        case .maintain: 0
        case .gain: 500
        }
    }

    public var displayName: String {
        switch self {
        case .lose: "Lose"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}

public enum CalorieTargetCalculator {

    /// Never suggest below a safe daily minimum.
    public static let floorKcal = 1_200

    /// Mifflin–St Jeor resting metabolic rate.
    /// Source: Mifflin MD, St Jeor ST, et al., "A new predictive equation for resting energy
    /// expenditure in healthy individuals", Am J Clin Nutr 1990;51(2):241–247:
    ///   RMR = 10·mass(kg) + 6.25·height(cm) − 5·age(y) + s,  s = +5 (male) / −161 (female)
    public static func bmr(_ profile: BodyProfile) -> Double {
        let sexTerm: Double = profile.sex == .male ? 5 : -161
        return 10 * profile.massKg
            + 6.25 * profile.heightCm
            - 5 * Double(profile.ageYears)
            + sexTerm
    }

    /// TDEE × goal delta, rounded to the nearest 50 kcal (false precision helps nobody),
    /// floored at `floorKcal`.
    public static func suggestedTarget(
        profile: BodyProfile,
        activity: ActivityLevel,
        goal: CalorieGoal
    ) -> Int {
        let tdee = bmr(profile) * activity.multiplier
        let raw = tdee + goal.deltaKcal
        let rounded = (raw / 50).rounded() * 50
        return max(floorKcal, Int(rounded))
    }
}

/// Where the suggestion's body data comes from (HealthKit phone-side; a fixed fake in the
/// simulator). `nil` = one or more inputs missing — indistinguishable from read-denied by
/// HealthKit design, so callers degrade to manual entry without accusing.
public protocol BodyProfileSource: Sendable {
    /// Deferred-contextual permission request (the target sheet calls it on open).
    func requestAuthorization() async throws
    func currentProfile() async throws -> BodyProfile?
}

public extension BodyProfileSource {
    func requestAuthorization() async throws {}   // fakes need no permission
}

/// One day's budget arithmetic — the single source of truth for the gauge and the hub line.
public struct DayBudget: Sendable, Equatable {
    public var targetKcal: Int
    public var consumedKcal: Double

    public init(targetKcal: Int, consumedKcal: Double) {
        self.targetKcal = targetKcal
        self.consumedKcal = max(0, consumedKcal)
    }

    /// Ring fill: clamped to one full lap — over-target NEVER starts a second lap (one ring,
    /// one variable; the over state is text + a single tint shift).
    public var fillFraction: Double {
        guard targetKcal > 0 else { return 0 }
        return min(consumedKcal / Double(targetKcal), 1)
    }

    public var isOver: Bool { consumedKcal > Double(targetKcal) }

    /// "230 over" — nil when at/under.
    public var overKcal: Int? {
        isOver ? Int((consumedKcal - Double(targetKcal)).rounded()) : nil
    }

    /// "580 left" — nil when over.
    public var remainingKcal: Int? {
        isOver ? nil : Int((Double(targetKcal) - consumedKcal).rounded())
    }
}
