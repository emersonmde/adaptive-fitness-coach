import Foundation
import Testing
@testable import AdaptiveCore

struct RunTrendTests {
    private let now = Date(timeIntervalSince1970: 1_751_900_000)

    private func dated(_ daysAgo: Int, runSeconds: TimeInterval, longest: TimeInterval = 120,
                       zone: TimeInterval = 300, drop: Double? = 20) -> DatedRunDigest {
        DatedRunDigest(
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            digest: RunDigest(runSeconds: runSeconds, walkSeconds: 300,
                              longestRunSeconds: longest,
                              timeInTargetZoneSeconds: zone,
                              meanRecoveryDrop: drop)
        )
    }

    @Test func emptyHistoryMakesAnEmptyTrend() {
        let trend = RunTrend.make(history: [], now: now)
        #expect(trend.sessionCount == 0)
        #expect(!trend.hasChart)
        #expect(trend.stats.isEmpty)
    }

    @Test func oneSessionHasStatsButNoChart() {
        let trend = RunTrend.make(history: [dated(2, runSeconds: 600)], now: now)
        #expect(trend.sessionCount == 1)
        #expect(!trend.hasChart)                     // a one-bar chart pretends a trend
        #expect(trend.stats.contains { $0.label == "Time running" })
        #expect(trend.stats.allSatisfy { $0.baselineSuffix == nil })   // no baseline yet
    }

    @Test func chartPointsAreWindowedAndAscending() {
        let history = [dated(40, runSeconds: 400), dated(20, runSeconds: 500),
                       dated(10, runSeconds: 550), dated(2, runSeconds: 600)]
        let trend = RunTrend.make(history: history.shuffled(), now: now)
        #expect(trend.points.count == 3)             // the 40-day-old run is out of window
        let minutes: [Double] = trend.points.map(\.minutesRunning)
        let expected: [Double] = [500, 550, 600].map { $0 / 60.0 }
        #expect(minutes == expected)
        #expect(trend.hasChart)
        #expect(trend.sessionCount == 4)
    }

    @Test func baselineSuffixesAppearOnlyPastTheGate() {
        // Four spread priors + today's run → the gate passes and suffixes render.
        let history = [dated(26, runSeconds: 480, longest: 100),
                       dated(18, runSeconds: 500, longest: 110),
                       dated(10, runSeconds: 520, longest: 120),
                       dated(4, runSeconds: 540, longest: 130),
                       dated(0, runSeconds: 660, longest: 210)]
        let trend = RunTrend.make(history: history, now: now)
        let longest = trend.stats.first { $0.label == "Longest run" }
        #expect(longest?.value == "3:30")
        #expect(longest?.baselineSuffix == "+1:35 vs 28-day average")   // 210 − mean(115) = 95s

        // Remove one prior → only 3 in-window priors → gate fails → bare values.
        let gated = RunTrend.make(history: Array(history.dropFirst()), now: now)
        #expect(gated.stats.allSatisfy { $0.baselineSuffix == nil })
    }

    @Test func absentSignalsProduceNoStatNotAZero() {
        let sparse = DatedRunDigest(
            date: now,
            digest: RunDigest(runSeconds: 600, walkSeconds: 300)   // no zone, no HRR, no longest
        )
        let trend = RunTrend.make(history: [sparse], now: now)
        #expect(!trend.stats.contains { $0.label == "In target zone" })
        #expect(!trend.stats.contains { $0.label == "HR recovery" })
        #expect(!trend.stats.contains { $0.label == "Longest run" })
        #expect(trend.stats.contains { $0.label == "Time running" })
    }
}
