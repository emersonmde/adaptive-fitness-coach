import Foundation

/// Suggests a post-run effort rating from the session's objective signals, so the complete
/// screen can pre-select a level instead of starting blank.
///
/// Grounded in the session-RPE literature: whole-session perceived exertion correlates
/// strongly (r ≈ 0.75–0.9) with heart-rate-derived load (Foster's session-RPE vs TRIMP), so
/// a coarse four-level suggestion from zone dwell + back-offs + recovery behavior is well
/// within what the correlation supports. The suggestion's product value is the *deviation*:
/// the progression gate already consumes the objective counters, so the informative signal is
/// the user changing "Moderate" to "All-out" — the fatigue-blindness the rating exists for.
///
/// Rules are ordered, explainable, and deliberately coarse — this is a suggestion for a
/// subjective question, never a measurement. Returns nil when the session carried no usable
/// HR/zone signal at all: a prefill from nothing would fabricate a signal (N6).
public enum EffortPredictor {
    /// Fraction of run time above the target zone that reads as a hard session.
    private static let hardAboveZoneFraction = 0.30
    /// Mean HRR drop (bpm) that, with an otherwise trouble-free session, reads as easy.
    private static let easyRecoveryDrop: Double = 25

    public static func suggestedLevel(from summary: SessionSummary) -> EffortLevel? {
        // No zone dwell and no recovery measurement → the session is signal-blind; suggest
        // nothing rather than guess (N6).
        guard summary.timeInTargetZone + summary.timeAboveTargetZone > 0
                || summary.meanRecoveryDrop != nil else { return nil }

        // Share the policy's own definitions (net cap hits, bailed early) so the suggestion
        // and progression can never classify the same session differently.
        let outcome = RunSessionOutcome(summary: summary)
        let netCapHits = outcome.netWalksHitCap

        if (outcome.bailedEarly && summary.runBackOffCount >= 1) || netCapHits >= 2 {
            return .allOut
        }

        let runTime = summary.totalRunDuration
        let aboveFraction = runTime > 0 ? summary.timeAboveTargetZone / runTime : 0
        if summary.runBackOffCount >= 2 || netCapHits >= 1 || aboveFraction > hardAboveZoneFraction {
            return .hard
        }

        if summary.runBackOffCount == 0, netCapHits == 0,
           summary.walksCompleted > 0, summary.fastRecoveries >= summary.walksCompleted,
           let drop = summary.meanRecoveryDrop, drop >= easyRecoveryDrop {
            return .easy
        }

        return .moderate
    }
}
