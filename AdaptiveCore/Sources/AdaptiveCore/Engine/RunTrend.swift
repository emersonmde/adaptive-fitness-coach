import Foundation

/// The phone Trends screen's model (P6.1): chart points + quiet stat lines for one routine,
/// derived from its dated run digests. Pure — the phone's Health reader feeds it, tests feed
/// it directly. Baseline suffixes reuse `RunComparison`'s gates so the watch summary and the
/// phone trends tell the same truth from the same rules.
public struct RunTrend: Sendable, Hashable {
    public struct Point: Sendable, Hashable {
        public let date: Date
        public let minutesRunning: Double

        public init(date: Date, minutesRunning: Double) {
            self.date = date
            self.minutesRunning = minutesRunning
        }
    }

    public struct Stat: Sendable, Hashable {
        public let label: String
        public let value: String
        /// "+1:50 vs 28-day average" — present only when the baseline gate passes AND the
        /// delta is outside the even band; nil renders as the bare value.
        public let baselineSuffix: String?

        public init(label: String, value: String, baselineSuffix: String? = nil) {
            self.label = label
            self.value = value
            self.baselineSuffix = baselineSuffix
        }
    }

    /// One bar per session inside the 28-day window, ascending by date.
    public let points: [Point]
    /// The most recent session (any age) — the stat lines describe it.
    public let latest: DatedRunDigest?
    /// Total digest-bearing sessions seen (drives the empty states).
    public let sessionCount: Int
    public let stats: [Stat]

    /// The chart needs ≥2 sessions in-window — a one-bar chart pretends a trend (N6).
    public var hasChart: Bool { points.count >= 2 }

    public static func make(history: [DatedRunDigest], now: Date = Date()) -> RunTrend {
        let sorted = history.sorted { $0.date < $1.date }
        let windowStart = now.addingTimeInterval(-Double(RunComparison.baselineWindowDays) * 86_400)
        let window = sorted.filter { $0.date >= windowStart }
        let points = window.map {
            Point(date: $0.date, minutesRunning: $0.digest.runSeconds / 60)
        }

        guard let latest = sorted.last else {
            return RunTrend(points: [], latest: nil, sessionCount: 0, stats: [])
        }

        // The latest session compares against the OTHER in-window sessions — same gate as
        // the watch summary's baseline line (≥4 runs spread over ≥21 days).
        let priors = window.filter { $0.date < latest.date }
        let gatePasses = priors.count >= RunComparison.baselineMinimumRuns
            && priors.map(\.date).min().map {
                now.timeIntervalSince($0) >= Double(RunComparison.baselineMinimumSpreadDays) * 86_400
            } == true

        var stats: [Stat] = []
        let digest = latest.digest

        if let fraction = digest.runFraction {
            let baseline = gatePasses ? mean(priors.compactMap(\.digest.runFraction)) : nil
            stats.append(Stat(
                label: "Time running",
                value: "\(Int((fraction * 100).rounded()))%",
                baselineSuffix: baseline.flatMap { avg in
                    percentSuffix(delta: (fraction - avg) * 100)
                }
            ))
        }
        if digest.longestRunSeconds > 0 {
            let baseline = gatePasses ? mean(priors.map(\.digest.longestRunSeconds).filter { $0 > 0 }) : nil
            stats.append(Stat(
                label: "Longest run",
                value: RunComparison.clock(digest.longestRunSeconds),
                baselineSuffix: baseline.flatMap { clockSuffix(delta: digest.longestRunSeconds - $0) }
            ))
        }
        if digest.timeInTargetZoneSeconds > 0 {
            let baseline = gatePasses
                ? mean(priors.map(\.digest.timeInTargetZoneSeconds).filter { $0 > 0 }) : nil
            stats.append(Stat(
                label: "In target zone",
                value: RunComparison.clock(digest.timeInTargetZoneSeconds),
                baselineSuffix: baseline.flatMap { clockSuffix(delta: digest.timeInTargetZoneSeconds - $0) }
            ))
        }
        if let drop = digest.meanRecoveryDrop {
            let baseline = gatePasses ? mean(priors.compactMap(\.digest.meanRecoveryDrop)) : nil
            stats.append(Stat(
                label: "HR recovery",
                value: "\(Int(drop.rounded())) bpm",
                baselineSuffix: baseline.flatMap { bpmSuffix(delta: drop - $0) }
            ))
        }

        return RunTrend(points: points, latest: latest, sessionCount: sorted.count, stats: stats)
    }

    // MARK: - Formatting (facts, never grades — signs, no colors, no judgment words)

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func clockSuffix(delta: TimeInterval) -> String? {
        guard abs(delta) >= 15 else { return nil }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(RunComparison.clock(abs(delta))) vs 28-day average"
    }

    private static func percentSuffix(delta: Double) -> String? {
        guard abs(delta) >= 3 else { return nil }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(Int(abs(delta).rounded()))% vs 28-day average"
    }

    private static func bpmSuffix(delta: Double) -> String? {
        guard abs(delta) >= 3 else { return nil }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(Int(abs(delta).rounded())) bpm vs 28-day average"
    }
}
