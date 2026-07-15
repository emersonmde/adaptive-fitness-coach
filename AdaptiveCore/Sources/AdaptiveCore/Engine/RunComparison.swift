import Foundation

/// A digest with the day it happened — the unit of run history read back from Health.
public struct DatedRunDigest: Sendable, Hashable {
    public let date: Date
    public let digest: RunDigest

    public init(date: Date, digest: RunDigest) {
        self.date = date
        self.digest = digest
    }
}

/// The quiet improvement lines on the run summary (P6.1): "vs last run" and "vs 28-day
/// baseline". Pure logic — the watch/phone feed it digests read from Health.
///
/// **The 28-day window is evidence, not taste:** the 7:28 acute:chronic workload ratio is
/// the most-investigated training-load construct in the sports-science literature (Gabbett
/// et al.), and Apple's own Training Load compares the last 7 days against the last 28 —
/// hiding the feature until 28 days of history exist. We mirror both the window and that
/// honesty gate: no baseline line until the history can actually support one.
///
/// Comparisons state facts, never grades (design principles — no shame): a downward delta
/// renders in neutral secondary, never red; `improved` exists only so the view may tint an
/// upward move in the run hue (more running is the hue's own quantity).
public enum RunComparison {
    public struct Line: Sendable, Hashable {
        /// "vs last run" / "vs 28-day baseline".
        public let label: String
        /// "+2:10 running" / "−1:30 running" / "even".
        public let delta: String
        /// true = more running (view may tint run-green); nil = effectively even.
        public let improved: Bool?

        public init(label: String, delta: String, improved: Bool?) {
            self.label = label
            self.delta = delta
            self.improved = improved
        }
    }

    /// Baseline gate: at least this many digest-bearing runs of the routine inside the window…
    public static let baselineMinimumRuns = 4
    /// …spread over at least this many days (four runs from last week aren't a baseline).
    public static let baselineMinimumSpreadDays = 21
    public static let baselineWindowDays = 28
    /// Deltas inside this band read as "even" — a ±10s line is noise, not information.
    static let evenBandSeconds: TimeInterval = 15

    /// vs the previous run of this routine. nil when none exists (pre-feature history has no
    /// digests — silence, never a fabricated zero). Aborted sessions never compare: an
    /// ended-early current run shows no delta (its numbers aren't the session that was
    /// planned), and an ended-early previous run is skipped by `lastComparable(in:)`.
    public static func vsLastRun(current: RunDigest, previous: RunDigest?) -> Line? {
        guard !current.endedEarly, let previous, !previous.endedEarly else { return nil }
        return line(label: "vs last run", delta: current.runSeconds - previous.runSeconds)
    }

    /// The most recent digest that can honestly serve as "last run" — skips aborts.
    /// `history` is newest-first, as both digest readers return it.
    public static func lastComparable(in history: [DatedRunDigest]) -> RunDigest? {
        history.first(where: { !$0.digest.endedEarly })?.digest
    }

    /// vs the mean of this routine's digest-bearing runs over the last 28 days. nil until the
    /// gate passes: ≥ `baselineMinimumRuns` in-window runs whose oldest is
    /// ≥ `baselineMinimumSpreadDays` old. Ended-early runs are excluded on both sides of the
    /// comparison — an abort is a fact for Health, not a baseline.
    public static func vsBaseline(current: RunDigest, history: [DatedRunDigest], now: Date = Date()) -> Line? {
        guard !current.endedEarly else { return nil }
        let windowStart = now.addingTimeInterval(-Double(baselineWindowDays) * 86_400)
        let window = history.filter { $0.date >= windowStart && $0.date < now && !$0.digest.endedEarly }
        guard window.count >= baselineMinimumRuns,
              let oldest = window.map(\.date).min(),
              now.timeIntervalSince(oldest) >= Double(baselineMinimumSpreadDays) * 86_400
        else { return nil }
        let mean = window.map(\.digest.runSeconds).reduce(0, +) / Double(window.count)
        return line(label: "vs 28-day baseline", delta: current.runSeconds - mean)
    }

    private static func line(label: String, delta: TimeInterval) -> Line {
        guard abs(delta) >= evenBandSeconds else {
            return Line(label: label, delta: "even", improved: nil)
        }
        let sign = delta > 0 ? "+" : "−"
        return Line(label: label,
                    delta: "\(sign)\(clock(abs(delta))) running",
                    improved: delta > 0)
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
