import Foundation

/// The adaptive energy budget — the build-22 successor to the fixed `DayBudget`.
///
/// Two pure pieces, both Foundation-only and exhaustively unit-tested:
///  - `DynamicDayBudget` computes today's "safe to eat" number as basal (banked up front) minus
///    the user's deficit plus active energy **realized as it is earned** — never forecast. The
///    final end-of-day value equals TDEE − deficit exactly; intraday it is a conservative running
///    tally that only ever counts calories the watch has already recorded.
///  - `EnergyBalanceCalibrator` learns a per-user correction from the Apple Health weight trend by
///    Bayesian shrinkage: the estimate starts at safe population defaults and migrates toward the
///    personal value as the weigh-in evidence's standard error drops below the prior's. No hard
///    threshold, no fixed wait — it tips toward personal at whatever cadence the user weighs in.
///
/// See `docs/ADAPTIVE-SYSTEM.md` and the plan for the science behind the constants.

// MARK: - Shared constants

public enum EnergyBudgetConstants {

    /// Trust multiplier applied to Apple Watch **active** energy. The watch systematically
    /// *overestimates* active energy — validation meta-analyses put the signed mean error roughly
    /// −7 %…+53 % with MAPE ≈ 28 %, predominantly positive — so a −20 % haircut lands near the true
    /// mean, biased slightly conservative. Erring low is the safe direction: over-discounting only
    /// enlarges an already-safe deficit, whereas trusting the watch banks phantom calories.
    /// Source: npj Digital Medicine living meta-analysis (2025); Apple Watch 6 validity, J Sci Med Sport (2023).
    public static let activeTrustDefault = 0.80

    /// No haircut on basal. Mifflin–St Jeor is *unbiased* at the population level (95 % CI ≈
    /// −26…+8 kcal/day) — its error is symmetric individual variance (~±10 %), not bias — so basal
    /// needs an uncertainty band (the prior SD), not a point shift. The weight calibration narrows
    /// that band per user. Source: Frankenfield, Clinical Nutrition (2013); JADA (2005).
    public static let basalTrustDefault = 1.0

    /// Energy density of body-mass change, for reverse-calculating TDEE from a weight trend
    /// (`TDEE = intake − Δweight_kg·7700/day`). Standard mixed-tissue rule; approximate because
    /// early water/glycogen shifts wash out only over ≥2–4 weeks — hence the trend fit, not
    /// endpoint-minus-endpoint.
    public static let tissueKcalPerKg = 7700.0

    /// The learned basal correction is clamped to this band so a noisy or short weight series can
    /// never drive an absurd target.
    public static let basalTrustBounds = 0.70...1.30

    /// Prior uncertainty on TDEE as a fraction of its point estimate (Mifflin individual spread ⊕
    /// active-sensor spread). Governs how much weight evidence must accrue before the posterior
    /// leaves the default.
    public static let priorTdeeCoefficientOfVariation = 0.10

    /// Never suggest an intake below this (mirrors `CalorieTargetCalculator.floorKcal`).
    public static let floorKcal = CalorieTargetCalculator.floorKcal
}

// MARK: - Dynamic day budget

/// One day's live budget. `activeEarnedKcal` is the *raw* watch active energy so far today; the
/// trust haircut is applied here, in one place. Consumed-vs-target arithmetic is delegated to the
/// existing `DayBudget` so the gauge keeps a single source of truth.
public struct DynamicDayBudget: Sendable, Equatable {
    public var bmrKcal: Double
    public var deficitKcal: Double
    public var activeEarnedKcal: Double
    public var consumedKcal: Double
    public var basalTrust: Double
    public var activeTrust: Double
    public var floorKcal: Int

    public init(
        bmrKcal: Double,
        deficitKcal: Double,
        activeEarnedKcal: Double,
        consumedKcal: Double,
        basalTrust: Double = EnergyBudgetConstants.basalTrustDefault,
        activeTrust: Double = EnergyBudgetConstants.activeTrustDefault,
        floorKcal: Int = EnergyBudgetConstants.floorKcal
    ) {
        self.bmrKcal = bmrKcal
        self.deficitKcal = deficitKcal
        self.activeEarnedKcal = max(0, activeEarnedKcal)
        self.consumedKcal = max(0, consumedKcal)
        self.basalTrust = basalTrust
        self.activeTrust = activeTrust
        self.floorKcal = floorKcal
    }

    /// Trusted active energy banked so far today.
    public var earnedTodayKcal: Int {
        Int((activeTrust * activeEarnedKcal / 10).rounded() * 10)
    }

    /// The model target before the safety floor. `basalTrust·BMR − deficit + activeTrust·active`.
    public var rawTargetKcal: Double {
        basalTrust * bmrKcal - deficitKcal + activeTrust * activeEarnedKcal
    }

    /// True when the raw model would land below the safe minimum — the deficit is (for now) capped
    /// by the floor and the rest is "earned" as the day's activity banks. Drives the gentle
    /// "at your safe minimum — move more to unlock your full deficit" hint.
    public var isAtFloor: Bool { rawTargetKcal < Double(floorKcal) }

    /// Displayed target, floored and rounded to the nearest 10 (it updates live, so 50-kcal steps
    /// would read as jumps; 10 avoids both jank and false precision).
    public var targetKcal: Int {
        max(floorKcal, Int((rawTargetKcal / 10).rounded() * 10))
    }

    /// Consumed rounded to whole kcal (the "eaten" term).
    public var consumedRoundedKcal: Int { Int(consumedKcal.rounded()) }

    /// **Signed** remaining (negative = over budget). Drives the one "N left" / "N over" line
    /// with no nil fallback — the label is chosen by sign, never by a null check, so it never
    /// flips to "Target". Equals the breakdown `base + active − eaten` exactly, by construction.
    public var remainingSignedKcal: Int { targetKcal - consumedRoundedKcal }

    /// The resting portion of a composed budget (budget − banked active). By construction
    /// `baseKcal + earnedTodayKcal == targetKcal`, so `base + active − eaten == remaining`.
    /// Not meaningful when `isAtFloor` (the budget then shows a single "floor" term).
    public var baseKcal: Int { targetKcal - earnedTodayKcal }

    /// Consumed-vs-target arithmetic, reusing the pinned `DayBudget`.
    public var budget: DayBudget {
        DayBudget(targetKcal: targetKcal, consumedKcal: consumedKcal)
    }

    public var fillFraction: Double { budget.fillFraction }
    public var isOver: Bool { budget.isOver }
    public var overKcal: Int? { budget.overKcal }
    public var remainingKcal: Int? { budget.remainingKcal }
}

// MARK: - Calibration

/// The learned per-user correction plus the metadata a UI needs to decide whether to show it.
public struct Calibration: Sendable, Equatable, Codable {
    /// Multiplier on Mifflin BMR — carries the whole learned residual (see identifiability note on
    /// `EnergyBalanceCalibrator`). 1.0 = the population default.
    public var basalTrust: Double
    /// Kept at the sensor prior; weight data cannot separate it from basal.
    public var activeTrust: Double
    /// Posterior mean daily TDEE (kcal).
    public var tdeeEstimateKcal: Double
    /// Posterior SD (kcal) — shrinks as evidence accrues.
    public var sdKcal: Double
    /// Days spanned by the weight series.
    public var spanDays: Int
    /// Number of weight samples used.
    public var weighInCount: Int
    /// Whether there is enough clean evidence to surface "tuned to your data" to the user.
    public var isConfident: Bool

    public init(
        basalTrust: Double,
        activeTrust: Double,
        tdeeEstimateKcal: Double,
        sdKcal: Double,
        spanDays: Int,
        weighInCount: Int,
        isConfident: Bool
    ) {
        self.basalTrust = basalTrust
        self.activeTrust = activeTrust
        self.tdeeEstimateKcal = tdeeEstimateKcal
        self.sdKcal = sdKcal
        self.spanDays = spanDays
        self.weighInCount = weighInCount
        self.isConfident = isConfident
    }

    /// How far the learned metabolism sits from the textbook estimate, as a signed percent
    /// (negative = runs below the estimate). `nil` until confident. For the plain-language note.
    public var deviationPercent: Int? {
        guard isConfident else { return nil }
        return Int(((basalTrust - 1.0) * 100).rounded())
    }
}

public enum EnergyBalanceCalibrator {

    /// Cold-start calibration: safe population defaults, not confident. Used until a weight trend
    /// exists (the stale/estimated-weight user stays here).
    public static func prior(
        profile: BodyProfile,
        avgActiveKcal: Double = 0,
        activeTrust: Double = EnergyBudgetConstants.activeTrustDefault
    ) -> Calibration {
        let bmr = CalorieTargetCalculator.bmr(profile)
        let tdee = bmr + activeTrust * max(0, avgActiveKcal)
        return Calibration(
            basalTrust: EnergyBudgetConstants.basalTrustDefault,
            activeTrust: activeTrust,
            tdeeEstimateKcal: tdee,
            sdKcal: tdee * EnergyBudgetConstants.priorTdeeCoefficientOfVariation,
            spanDays: 0,
            weighInCount: 0,
            isConfident: false
        )
    }

    /// Learn a correction from trailing daily series.
    ///
    /// **Identifiability:** a weight trend constrains only *total* TDEE, never basal vs active
    /// separately, so the entire learned residual is folded into `basalTrust` (personal metabolism
    /// is the dominant unknown weight reveals); `activeTrust` stays at its sensor-derived prior.
    ///
    /// The estimate is a precision-weighted blend of the population prior and the weight-derived
    /// observation `TDEE_obs = meanIntake − slope·7700`. Thin, noisy, or low-coverage data yields a
    /// large observation SE, so the posterior simply stays near the safe prior.
    public static func calibrate(
        weights: [(date: Date, kg: Double)],
        dailyIntakeKcal: [(date: Date, kcal: Double)],
        dailyActiveKcal: [(date: Date, kcal: Double)],
        profile: BodyProfile,
        activeTrust: Double = EnergyBudgetConstants.activeTrustDefault,
        calendar: Calendar = .current
    ) -> Calibration {
        let bmr = CalorieTargetCalculator.bmr(profile)
        let avgActive = mean(dailyActiveKcal.map(\.kcal)) ?? 0
        let prior = prior(profile: profile, avgActiveKcal: avgActive, activeTrust: activeTrust)

        // Clean the weight series: drop physiologically impossible samples, order by day.
        let clean = weights
            .filter { $0.kg > 30 && $0.kg < 400 }
            .sorted { $0.date < $1.date }
        guard let first = clean.first, let last = clean.last else { return prior }
        let spanDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                               to: calendar.startOfDay(for: last.date)).day ?? 0

        // Linear weight trend (kg/day). Needs ≥3 points spanning ≥1 day for a slope + its SE.
        let points = clean.map { (x: dayOffset($0.date, from: first.date, calendar), y: $0.kg) }
        guard let fit = linearFit(points) else { return prior }

        // Mean intake over the window, and how many of those days were actually logged.
        let windowStart = calendar.startOfDay(for: first.date)
        let windowEnd = calendar.startOfDay(for: last.date)
        let intakeInWindow = dailyIntakeKcal
            .filter { $0.kcal > 0 }
            .filter { calendar.startOfDay(for: $0.date) >= windowStart && calendar.startOfDay(for: $0.date) <= windowEnd }
            .map(\.kcal)
        guard let meanIntake = mean(intakeInWindow) else { return prior }
        let coverage = min(1.0, Double(intakeInWindow.count) / Double(max(1, spanDays + 1)))

        // Energy balance: slope·7700 = meanIntake − TDEE  ⇒  TDEE_obs = meanIntake − slope·7700.
        let tdeeObs = meanIntake - fit.slope * EnergyBudgetConstants.tissueKcalPerKg

        // Observation SE: weight-slope uncertainty ⊕ mean-intake uncertainty, inflated when intake
        // logging is sparse, floored so perfectly clean synthetic data can't claim infinite precision.
        let slopeSE = EnergyBudgetConstants.tissueKcalPerKg * fit.seSlope
        let intakeSE = (standardDeviation(intakeInWindow) ?? 0) / Double(intakeInWindow.count).squareRoot()
        var seObs = (slopeSE * slopeSE + intakeSE * intakeSE).squareRoot()
        seObs /= max(0.0001, coverage).squareRoot()
        seObs = max(seObs, 15)

        // Precision-weighted posterior.
        let wObs = 1 / (seObs * seObs)
        let wPrior = 1 / (prior.sdKcal * prior.sdKcal)
        let tdeePost = (wObs * tdeeObs + wPrior * prior.tdeeEstimateKcal) / (wObs + wPrior)
        let sdPost = (1 / (wObs + wPrior)).squareRoot()

        // Fold the whole residual into basal (active stays at prior); clamp to the safe band.
        let rawBasalTrust = (tdeePost - activeTrust * avgActive) / bmr
        let basalTrust = min(max(rawBasalTrust, EnergyBudgetConstants.basalTrustBounds.lowerBound),
                             EnergyBudgetConstants.basalTrustBounds.upperBound)

        let confident = spanDays >= 14
            && clean.count >= 8
            && coverage >= 0.5
            && seObs < prior.sdKcal

        return Calibration(
            basalTrust: basalTrust,
            activeTrust: activeTrust,
            tdeeEstimateKcal: tdeePost,
            sdKcal: sdPost,
            spanDays: spanDays,
            weighInCount: clean.count,
            isConfident: confident
        )
    }

    // MARK: - Numeric helpers

    private static func dayOffset(_ date: Date, from origin: Date, _ calendar: Calendar) -> Double {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: origin),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return Double(days)
    }

    private static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func standardDeviation(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let ss = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(xs.count - 1)).squareRoot()
    }

    /// Ordinary least-squares slope and its standard error. Returns nil when the fit is
    /// underdetermined (<3 points) or the x's don't vary (all samples same day).
    private static func linearFit(_ points: [(x: Double, y: Double)]) -> (slope: Double, seSlope: Double)? {
        let n = points.count
        guard n >= 3 else { return nil }
        let meanX = points.reduce(0) { $0 + $1.x } / Double(n)
        let meanY = points.reduce(0) { $0 + $1.y } / Double(n)
        let sxx = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let sse = points.reduce(0.0) { acc, p in
            let residual = p.y - (intercept + slope * p.x)
            return acc + residual * residual
        }
        let residualVariance = sse / Double(n - 2)
        let seSlope = (residualVariance / sxx).squareRoot()
        return (slope, seSlope)
    }
}
