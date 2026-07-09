import Foundation
import AdaptiveCore

/// The user's daily calorie *goal* — a setting, not food data (C5: no nutrition ever lives
/// outside Health). UserDefaults-backed, `@Observable` so the gauge and hub line re-render on
/// change; ephemeral under `-uiTesting`.
///
/// Two modes:
///  - **Deficit** (the build-22 default when Health has body data): the user picks a kcal/day
///    deficit; the daily budget is `basalTrust·BMR − deficit + activeTrust·activeEarned`, i.e. it
///    rises through the day as active energy banks. `basalTrust` is learned per-user from the
///    weight trend (`refreshCalibration`).
///  - **Fixed** (manual fallback when Health lacks body data): a plain number, the old behavior.
@MainActor
@Observable
final class CalorieTargetStore {

    private static let deficitKey = "calorieDeficitKcal"
    private static let deficitSetKey = "calorieDeficitSet"   // deficit can be 0 (maintain) / negative (surplus)
    private static let fixedKey = "calorieFixedTargetKcal"
    private static let goalKey = "calorieTargetGoal"
    private static let offeredKey = "calorieTargetOffered"
    private static let bmrKey = "calorieBmrKcal"
    private static let calibrationKey = "calorieCalibration"
    private static let lastCalibrationKey = "calorieLastCalibration"

    private let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// Deficit-mode primitive (kcal/day). Non-nil ⇒ deficit mode.
    private(set) var deficitKcal: Int?
    /// Fixed-mode manual number. Non-nil ⇒ fixed mode.
    private(set) var fixedTargetKcal: Int?
    /// Cached resting metabolic rate (Mifflin) for the current body — refreshed from Health.
    private(set) var bmrKcal: Double?
    /// The learned correction; nil until the first calibration. Drives `basalTrust`.
    private(set) var calibration: Calibration?
    private(set) var goal: CalorieGoal?
    private(set) var wasOffered: Bool
    private var lastCalibration: Date?

    private let bodyProfileSource: any BodyProfileSource
    private let energyHistorySource: any EnergyHistorySource

    init(
        bodyProfileSource: any BodyProfileSource,
        energyHistorySource: any EnergyHistorySource
    ) {
        self.bodyProfileSource = bodyProfileSource
        self.energyHistorySource = energyHistorySource
        // Initialize every stored property before any load logic reads back via `self`.
        deficitKcal = nil; fixedTargetKcal = nil; bmrKcal = nil
        calibration = nil; goal = nil; wasOffered = false; lastCalibration = nil
        guard !ephemeral else { return }

        let defaults = UserDefaults.standard
        deficitKcal = defaults.bool(forKey: Self.deficitSetKey) ? defaults.integer(forKey: Self.deficitKey) : nil
        fixedTargetKcal = Self.positiveInt(defaults, Self.fixedKey)
        // No migration of the pre-build-22 fixed number: the target is a preference, not data
        // (all meals/weight/energy live in Health). A returning user simply re-picks a deficit —
        // which then reflects all their existing Health history — rather than being stranded on
        // the old fixed-number mode. The stale legacy key, if any, is inert (nothing reads it).
        goal = defaults.string(forKey: Self.goalKey).flatMap(CalorieGoal.init(rawValue:))
        wasOffered = defaults.bool(forKey: Self.offeredKey)
        let storedBmr = defaults.double(forKey: Self.bmrKey)
        bmrKcal = storedBmr > 0 ? storedBmr : nil
        calibration = defaults.data(forKey: Self.calibrationKey)
            .flatMap { try? JSONDecoder().decode(Calibration.self, from: $0) }
        let last = defaults.double(forKey: Self.lastCalibrationKey)
        lastCalibration = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    // MARK: - Derived

    var hasTarget: Bool { deficitKcal != nil || fixedTargetKcal != nil }

    var basalTrust: Double { calibration?.basalTrust ?? EnergyBudgetConstants.basalTrustDefault }
    var activeTrust: Double { calibration?.activeTrust ?? EnergyBudgetConstants.activeTrustDefault }

    /// Back-compat headline number (export pack, hub line): the fixed number, or — in deficit
    /// mode — the *resting* baseline (before any active energy is earned).
    var target: Int? {
        if let fixedTargetKcal { return fixedTargetKcal }
        return dynamicBudget(consumedKcal: 0, activeEarnedKcal: 0)?.targetKcal
    }

    /// The live budget for one day. `activeEarnedKcal` is the raw watch active energy so far
    /// (full-day total for a past day); the trust haircut is applied inside `DynamicDayBudget`.
    /// Non-nil only in deficit mode with a known BMR.
    func dynamicBudget(consumedKcal: Double, activeEarnedKcal: Double) -> DynamicDayBudget? {
        guard let deficitKcal, let bmrKcal else { return nil }
        return DynamicDayBudget(
            bmrKcal: bmrKcal,
            deficitKcal: Double(deficitKcal),
            activeEarnedKcal: activeEarnedKcal,
            consumedKcal: consumedKcal,
            basalTrust: basalTrust,
            activeTrust: activeTrust
        )
    }

    /// Fixed-mode budget (nil in deficit mode).
    func budget(consumedKcal: Double) -> DayBudget? {
        guard let fixedTargetKcal else { return nil }
        return DayBudget(targetKcal: fixedTargetKcal, consumedKcal: consumedKcal)
    }

    // MARK: - Mutation

    /// Deficit mode: `deficitKcal` is how far *below* maintenance to aim (e.g. 1000). Caches the
    /// BMR so the gauge can render immediately without a profile fetch.
    func setDeficit(_ deficit: Int, goal newGoal: CalorieGoal?, bmrKcal newBmr: Double) {
        deficitKcal = deficit          // 0 = maintain, negative = surplus
        fixedTargetKcal = nil
        bmrKcal = newBmr
        goal = newGoal
        markOffered()
        guard !ephemeral else { return }
        let defaults = UserDefaults.standard
        defaults.set(deficit, forKey: Self.deficitKey)
        defaults.set(true, forKey: Self.deficitSetKey)
        defaults.removeObject(forKey: Self.fixedKey)
        defaults.set(newBmr, forKey: Self.bmrKey)
        defaults.set(newGoal?.rawValue, forKey: Self.goalKey)
    }

    /// Fixed mode: a plain manual number (Health lacked the body data for a deficit budget).
    func setFixed(_ target: Int) {
        fixedTargetKcal = max(0, target) == 0 ? nil : target
        deficitKcal = nil
        goal = nil
        markOffered()
        guard !ephemeral else { return }
        let defaults = UserDefaults.standard
        defaults.set(target, forKey: Self.fixedKey)
        defaults.removeObject(forKey: Self.deficitKey)
        defaults.removeObject(forKey: Self.deficitSetKey)
    }

    func clear() {
        deficitKcal = nil; fixedTargetKcal = nil; goal = nil; calibration = nil; bmrKcal = nil
        guard !ephemeral else { return }
        let defaults = UserDefaults.standard
        [Self.deficitKey, Self.deficitSetKey, Self.fixedKey, Self.goalKey, Self.bmrKey,
         Self.calibrationKey, Self.lastCalibrationKey].forEach { defaults.removeObject(forKey: $0) }
    }

    func markOffered() {
        wasOffered = true
        guard !ephemeral else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
    }

    // MARK: - Calibration

    /// Refresh the cached BMR and the learned correction from Apple Health. Throttled to once a
    /// day (weight trends move over weeks — nothing to gain from recomputing more often). No-op
    /// outside deficit mode, or when Health lacks a body profile.
    func refreshCalibration(asOf day: Date = Date(), force: Bool = false) async {
        guard deficitKcal != nil else { return }
        if !force, let last = lastCalibration,
           Calendar.current.isDate(last, inSameDayAs: day) { return }

        guard let profile = try? await bodyProfileSource.currentProfile() else { return }
        let freshBmr = CalorieTargetCalculator.bmr(profile)

        let history = (try? await energyHistorySource.history(trailingDays: 28, endingOn: day))
            ?? EnergyHistory()
        let result = EnergyBalanceCalibrator.calibrate(history: history, profile: profile)

        bmrKcal = freshBmr
        calibration = result
        lastCalibration = day
        guard !ephemeral else { return }
        let defaults = UserDefaults.standard
        defaults.set(freshBmr, forKey: Self.bmrKey)
        if let data = try? JSONEncoder().encode(result) {
            defaults.set(data, forKey: Self.calibrationKey)
        }
        defaults.set(day.timeIntervalSince1970, forKey: Self.lastCalibrationKey)
    }

    private static func positiveInt(_ defaults: UserDefaults, _ key: String) -> Int? {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }
}
