import Foundation

/// The coarse post-workout effort vocabulary (P6.1) — what the user actually thinks in
/// ("that was hard"), replacing the 1–10 number as the *input*. The 1–10 scale survives
/// underneath untouched: `score` is what's written to `HKWorkoutEffortScore` (a hard 1–10
/// Apple scale) and fed to the progression policies, so the wire format, the journal, and
/// `highEffortThreshold` all keep working on plain `Int`s.
///
/// The scores are chosen against the policies' `highEffortThreshold = 8`: **Hard and All-out
/// both hold progression** (user decision) — `hard.score == 8` sits exactly at the threshold.
/// `EffortLevelTests` pins that invariant so a future threshold tweak can't silently break it.
public enum EffortLevel: Int, CaseIterable, Sendable, Codable {
    case easy
    case moderate
    case hard
    case allOut

    /// The 1–10 value this level records (HKWorkoutEffortScore + policy input).
    public var score: Int {
        switch self {
        case .easy: return 2
        case .moderate: return 5
        case .hard: return 8
        case .allOut: return 10
        }
    }

    public var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .allOut: return "All-out"
        }
    }

    /// Bucket an arbitrary 1–10 score back to a level (journal display of historical
    /// fine-grained ratings). Out-of-range scores return nil rather than a guess.
    public init?(score: Int) {
        switch score {
        case 1...3: self = .easy
        case 4...6: self = .moderate
        case 7...8: self = .hard
        case 9...10: self = .allOut
        default: return nil
        }
    }

    /// The next level up, or nil at the top.
    public var up: EffortLevel? { EffortLevel(rawValue: rawValue + 1) }
    /// The next level down, or nil at the bottom (the caller collapses to unrated).
    public var down: EffortLevel? { EffortLevel(rawValue: rawValue - 1) }
}
