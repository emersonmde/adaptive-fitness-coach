import Foundation
import Testing
@testable import AdaptiveCore

struct RunComparisonTests {
    private let now = Date(timeIntervalSince1970: 1_751_800_000)

    private func digest(runSeconds: TimeInterval) -> RunDigest {
        RunDigest(runSeconds: runSeconds, walkSeconds: 300)
    }

    private func dated(_ daysAgo: Int, runSeconds: TimeInterval) -> DatedRunDigest {
        DatedRunDigest(date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                       digest: digest(runSeconds: runSeconds))
    }

    // MARK: - vs last run

    @Test func noPreviousRunMeansSilence() {
        #expect(RunComparison.vsLastRun(current: digest(runSeconds: 600), previous: nil) == nil)
    }

    @Test func moreRunningReadsAsImproved() throws {
        let line = try #require(RunComparison.vsLastRun(
            current: digest(runSeconds: 730), previous: digest(runSeconds: 600)))
        #expect(line.delta == "+2:10 running")
        #expect(line.improved == true)
    }

    @Test func lessRunningIsAFactNotAGrade() throws {
        let line = try #require(RunComparison.vsLastRun(
            current: digest(runSeconds: 510), previous: digest(runSeconds: 600)))
        #expect(line.delta == "−1:30 running")
        #expect(line.improved == false)
    }

    @Test func tinyDeltasReadAsEven() throws {
        let line = try #require(RunComparison.vsLastRun(
            current: digest(runSeconds: 608), previous: digest(runSeconds: 600)))
        #expect(line.delta == "even")
        #expect(line.improved == nil)
    }

    // MARK: - vs 28-day baseline (the honesty gate)

    @Test func threeRunsAreNotABaseline() {
        let history = [dated(25, runSeconds: 500), dated(15, runSeconds: 550), dated(5, runSeconds: 600)]
        #expect(RunComparison.vsBaseline(current: digest(runSeconds: 700),
                                         history: history, now: now) == nil)
    }

    @Test func fourRecentRunsWithoutSpreadAreNotABaseline() {
        // Four runs all inside the last 10 days — enough count, not enough history.
        let history = [dated(10, runSeconds: 500), dated(7, runSeconds: 520),
                       dated(4, runSeconds: 540), dated(2, runSeconds: 560)]
        #expect(RunComparison.vsBaseline(current: digest(runSeconds: 700),
                                         history: history, now: now) == nil)
    }

    @Test func gatePassesWithFourSpreadRuns() throws {
        let history = [dated(26, runSeconds: 500), dated(18, runSeconds: 520),
                       dated(10, runSeconds: 540), dated(3, runSeconds: 560)]
        let line = try #require(RunComparison.vsBaseline(
            current: digest(runSeconds: 640), history: history, now: now))
        // Mean = 530 → +110s = +1:50.
        #expect(line.label == "vs 28-day baseline")
        #expect(line.delta == "+1:50 running")
        #expect(line.improved == true)
    }

    @Test func runsOutsideTheWindowDoNotCount() {
        // The 30- and 35-day-old runs fall outside the 28-day window → only 3 remain.
        let history = [dated(35, runSeconds: 500), dated(30, runSeconds: 500),
                       dated(22, runSeconds: 520), dated(10, runSeconds: 540),
                       dated(3, runSeconds: 560)]
        #expect(RunComparison.vsBaseline(current: digest(runSeconds: 640),
                                         history: history, now: now) == nil)
    }

    @Test func windowConstantsMatchTheEvidence() {
        // 7:28 ACWR (Gabbett; Apple Training Load) — the 28-day chronic window is the point.
        #expect(RunComparison.baselineWindowDays == 28)
        #expect(RunComparison.baselineMinimumRuns == 4)
    }
}
