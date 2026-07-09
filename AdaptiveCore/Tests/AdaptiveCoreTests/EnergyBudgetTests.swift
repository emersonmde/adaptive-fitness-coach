import Foundation
import Testing
@testable import AdaptiveCore

// MARK: - Golden constants & dynamic budget arithmetic

struct DynamicDayBudgetTests {

    private let profile = BodyProfile(massKg: 80, heightCm: 180, ageYears: 35, sex: .male)  // Mifflin BMR = 1755

    @Test func activeTrustDefaultSitsInResearchedBand() {
        // Apple Watch overestimates active energy; the −20% haircut must stay in the 0.75–0.85 band.
        #expect(EnergyBudgetConstants.activeTrustDefault >= 0.75)
        #expect(EnergyBudgetConstants.activeTrustDefault <= 0.85)
        // Basal is unbiased → no haircut.
        #expect(EnergyBudgetConstants.basalTrustDefault == 1.0)
    }

    @Test func earnedActiveIsHaircutAndBanked() {
        let bmr = CalorieTargetCalculator.bmr(profile)
        let b = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 500, activeEarnedKcal: 400,
                                 consumedKcal: 0, activeTrust: 0.80)
        // 0.80 × 400 = 320 banked.
        #expect(b.earnedTodayKcal == 320)
        // raw = 1755 − 500 + 320 = 1575.
        #expect(abs(b.rawTargetKcal - 1575) < 0.001)
        #expect(b.targetKcal == 1580)   // rounded to nearest 10
        #expect(!b.isAtFloor)
    }

    @Test func endOfDayBudgetEqualsTdeeMinusDeficit() {
        let bmr = CalorieTargetCalculator.bmr(profile)   // 1755
        let fullDayActive = 700.0
        let deficit = 500.0
        let b = DynamicDayBudget(bmrKcal: bmr, deficitKcal: deficit, activeEarnedKcal: fullDayActive,
                                 consumedKcal: 0, basalTrust: 1.0, activeTrust: 0.80)
        // TDEE = 1755 + 0.80×700 = 2315; − deficit 500 = 1815.
        #expect(abs(b.rawTargetKcal - 1815) < 0.001)
    }

    @Test func budgetGrowsMonotonicallyAsActiveBanks() {
        let bmr = CalorieTargetCalculator.bmr(profile)
        let morning = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 800, activeEarnedKcal: 0, consumedKcal: 0)
        let midday = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 800, activeEarnedKcal: 300, consumedKcal: 0)
        let evening = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 800, activeEarnedKcal: 650, consumedKcal: 0)
        #expect(morning.targetKcal <= midday.targetKcal)
        #expect(midday.targetKcal <= evening.targetKcal)
    }

    @Test func aggressiveDeficitPinsToFloorUntilEarned() {
        let bmr = CalorieTargetCalculator.bmr(profile)   // 1755
        // 1000 deficit off basal alone → 755, below the 1200 floor.
        let idle = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 1000, activeEarnedKcal: 0, consumedKcal: 0)
        #expect(idle.isAtFloor)
        #expect(idle.targetKcal == EnergyBudgetConstants.floorKcal)
        // Once enough active banks, the raw target clears the floor and the hint clears.
        let active = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 1000, activeEarnedKcal: 900, consumedKcal: 0)
        #expect(!active.isAtFloor)
        #expect(active.targetKcal > EnergyBudgetConstants.floorKcal)
    }

    @Test func breakdownAlwaysReconcilesToRemaining() {
        // The governing UI invariant: base + active − eaten == remaining, in every state.
        let bmr = CalorieTargetCalculator.bmr(profile)
        for (deficit, active, consumed) in [(500.0, 400.0, 140.0),   // normal
                                            (500.0, 0.0, 0.0),        // morning, nothing yet
                                            (300.0, 600.0, 2500.0),   // over budget
                                            (1000.0, 900.0, 300.0)] { // aggressive deficit
            let b = DynamicDayBudget(bmrKcal: bmr, deficitKcal: deficit, activeEarnedKcal: active,
                                     consumedKcal: consumed, basalTrust: 1.0, activeTrust: 0.80)
            if !b.isAtFloor {
                #expect(b.baseKcal + b.earnedTodayKcal - b.consumedRoundedKcal == b.remainingSignedKcal)
            }
            // Floor case: budget(floor) − eaten == remaining likewise.
            #expect(b.targetKcal - b.consumedRoundedKcal == b.remainingSignedKcal)
        }
    }

    @Test func consumedArithmeticDelegatesToDayBudget() {
        let bmr = CalorieTargetCalculator.bmr(profile)
        let b = DynamicDayBudget(bmrKcal: bmr, deficitKcal: 0, activeEarnedKcal: 0, consumedKcal: 1000)
        // target = 1755 → 1760.
        #expect(b.remainingKcal == 760)
        #expect(!b.isOver)
    }
}

// MARK: - Calibrator: validated against synthetic ground truth (science, not slow weigh-ins)

struct EnergyBalanceCalibratorTests {

    /// A profile whose *true* metabolism runs below the Mifflin estimate — this is what the
    /// calibration must discover. Mifflin BMR of this profile = 1755.
    private let profile = BodyProfile(massKg: 80, heightCm: 180, ageYears: 35, sex: .male)
    private static let mifflinBMR = 1755.0
    private let trueBasalFactor = 0.90            // real BMR is 10% below the textbook estimate
    private let trueActiveMean = 500.0            // real active energy actually expended
    private let watchOverestimate = 1.25          // 0.80 haircut × 1.25 = 1.0 → active handled exactly
    private let intakePerDay = 1800.0             // a genuine deficit

    private var trueBMR: Double { Self.mifflinBMR * trueBasalFactor }              // 1579.5
    private var trueTDEE: Double { trueBMR + trueActiveMean }                      // 2079.5

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // A tiny deterministic PRNG so the "random" simulation is reproducible across runs.
    private struct LCG {
        var state: UInt64
        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        mutating func gaussian(_ mean: Double, _ sd: Double) -> Double {
            let u1 = Swift.max(nextUnit(), 1e-12), u2 = nextUnit()
            let z = (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * Double.pi * u2)
            return mean + sd * z
        }
    }

    private struct Series {
        var weights: [(date: Date, kg: Double)]
        var intake: [(date: Date, kcal: Double)]
        var active: [(date: Date, kcal: Double)]
    }

    /// Simulate `days` of an energy-balance world: real daily TDEE drives the true weight path;
    /// the scale adds water noise; the watch reports inflated active energy. `weighInEvery` and
    /// `intakeCoverage` model imperfect adherence.
    private func simulate(days: Int, seed: UInt64, waterSD: Double = 0.4,
                          weighInEvery: Int = 1, intakeCoverage: Double = 1.0) -> Series {
        let cal = utcCalendar
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var rng = LCG(state: seed)
        var weightKg = 80.0
        var series = Series(weights: [], intake: [], active: [])
        for day in 0..<days {
            let date = base.addingTimeInterval(Double(day) * 86_400)
            let trueActiveToday = Swift.max(0, rng.gaussian(trueActiveMean, 150))
            let trueTdeeToday = trueBMR + trueActiveToday
            // Deterministic weight update from the real imbalance, plus reversible water noise.
            weightKg += (intakePerDay - trueTdeeToday) / EnergyBudgetConstants.tissueKcalPerKg
            let scaleReading = weightKg + rng.gaussian(0, waterSD)
            if day % weighInEvery == 0 {
                series.weights.append((date: date, kg: scaleReading))
            }
            if rng.nextUnit() <= intakeCoverage {
                series.intake.append((date: date, kcal: intakePerDay))
            }
            let watchActive = Swift.max(0, trueActiveToday * watchOverestimate + rng.gaussian(0, 40))
            series.active.append((date: date, kcal: watchActive))
        }
        return series
    }

    private func calibrate(_ s: Series) -> Calibration {
        EnergyBalanceCalibrator.calibrate(
            weights: s.weights, dailyIntakeKcal: s.intake, dailyActiveKcal: s.active,
            profile: profile, calendar: utcCalendar
        )
    }

    @Test func priorIsSafeDefaultWhenNoWeightData() {
        let c = EnergyBalanceCalibrator.prior(profile: profile, avgActiveKcal: 500)
        #expect(c.basalTrust == 1.0)
        #expect(!c.isConfident)
        #expect(c.deviationPercent == nil)
        // Empty series returns exactly the prior.
        let empty = calibrate(Series(weights: [], intake: [], active: []))
        #expect(empty.basalTrust == 1.0)
        #expect(!empty.isConfident)
    }

    @Test func recoversTrueMetabolismAcrossManySeeds() {
        // Average over seeds to strip simulation noise: the estimator must be ~unbiased toward truth,
        // not merely lucky on one seed. 42 days keeps the residual shrinkage bias small.
        var recovered: [Double] = []
        for seed in UInt64(1)...UInt64(30) {
            recovered.append(calibrate(simulate(days: 42, seed: seed)).basalTrust)
        }
        let avg = recovered.reduce(0, +) / Double(recovered.count)
        // True factor 0.90; posterior sits between truth and the 1.0 prior — must land much closer to truth.
        #expect(abs(avg - trueBasalFactor) < 0.025)
        #expect(abs(avg - trueBasalFactor) < abs(1.0 - trueBasalFactor) * 0.5)   // beats the prior by >2×
    }

    @Test func confidentCalibrationReportsPlausibleDeviation() {
        let c = calibrate(simulate(days: 30, seed: 7))
        #expect(c.isConfident)
        #expect(c.spanDays >= 14)
        #expect(c.weighInCount >= 8)
        #expect(abs(c.tdeeEstimateKcal - trueTDEE) < 120)
        let deviation = try? #require(c.deviationPercent)
        // ~−10% (runs below the textbook estimate).
        #expect((deviation ?? 0) <= -5 && (deviation ?? 0) >= -15)
    }

    @Test func posteriorTightensAndBeatsPriorAsEvidenceAccrues() {
        // One long simulation, read at growing windows: SD must shrink and error must fall below
        // the prior's as the weeks accumulate.
        let full = simulate(days: 42, seed: 3)
        func window(_ days: Int) -> Calibration {
            calibrate(Series(
                weights: full.weights.filter { $0.date <= full.weights[0].date.addingTimeInterval(Double(days) * 86_400) },
                intake: full.intake.filter { $0.date <= full.intake[0].date.addingTimeInterval(Double(days) * 86_400) },
                active: full.active
            ))
        }
        let short = window(10), mid = window(21), long = window(42)
        #expect(long.sdKcal < mid.sdKcal)
        #expect(mid.sdKcal < short.sdKcal)
        let priorError = abs(1.0 - trueBasalFactor)
        #expect(abs(long.basalTrust - trueBasalFactor) < priorError)   // personal beats default
        #expect(!short.isConfident)                                    // 10 days: not yet
        #expect(long.isConfident)                                      // 6 weeks: yes
    }

    @Test func reportedSDIsCalibratedAgainstActualError() {
        // The reported posterior SD should be the right order of magnitude for the real spread of
        // the estimate around truth — not wildly over- or under-confident.
        var errors: [Double] = []
        var sds: [Double] = []
        for seed in UInt64(100)...UInt64(140) {
            let c = calibrate(simulate(days: 28, seed: seed))
            errors.append(c.tdeeEstimateKcal - trueTDEE)
            sds.append(c.sdKcal)
        }
        let rms = (errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot()
        let meanSD = sds.reduce(0, +) / Double(sds.count)
        // Within a factor of ~2.5 in either direction is "calibrated" for this approximate model.
        #expect(rms < meanSD * 2.5)
        #expect(rms > meanSD * 0.4)
    }

    @Test func guardrailsHoldOnThinOrNoisyData() {
        // Too few weigh-ins: not confident, and the clamp keeps basalTrust sane.
        let sparse = calibrate(simulate(days: 30, seed: 5, weighInEvery: 12))   // ~3 weigh-ins
        #expect(!sparse.isConfident)
        #expect(EnergyBudgetConstants.basalTrustBounds.contains(sparse.basalTrust))

        // Huge water noise over a short span: stays near the prior and not confident.
        let noisy = calibrate(simulate(days: 12, seed: 9, waterSD: 2.5))
        #expect(!noisy.isConfident)
        #expect(abs(noisy.basalTrust - 1.0) < 0.15)

        // Poor intake logging: not confident even with many weigh-ins.
        let underlogged = calibrate(simulate(days: 30, seed: 11, intakeCoverage: 0.25))
        #expect(!underlogged.isConfident)
    }

    @Test func basalTrustNeverEscapesSafeBand() {
        // An extreme (implausible) intake can't drive the target outside the clamp.
        var s = simulate(days: 28, seed: 2)
        s.intake = s.intake.map { (date: $0.date, kcal: 6000.0) }   // absurd over-logging
        let c = calibrate(s)
        #expect(EnergyBudgetConstants.basalTrustBounds.contains(c.basalTrust))
    }
}
