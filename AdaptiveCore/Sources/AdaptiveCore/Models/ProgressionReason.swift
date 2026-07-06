import Foundation

/// Why a progression decision went the way it did — the "why" the P6 journal renders next to
/// each seed change ("Bicep Curl 12 → 13 reps — clean session").
///
/// The policies always *computed* this classification and threw it away; P6 makes it a
/// first-class output of `evaluate(...)` on both policies. On the wire and in the journal the
/// reason travels as its rendered `summary` string (not this enum), so adding cases later can
/// never break the codec's exact-version decode.
public enum ProgressionReason: Sendable, Hashable {
    // Advance-direction evidence.
    case cleanSession
    /// Every planned walk ended at the recovery floor — the two-notch run advance.
    case strongSession
    /// A run sustained well past the seed — the seed snaps to demonstrated capacity.
    case snapToCapacity
    /// The rep band topped out — the load step-up (the structural strength move P6 gates).
    case bandTopped

    // Hold evidence.
    /// Clean by the counters, but the session was rated at/above the high-effort threshold.
    case highEffort(Int)
    /// Rests kept hitting the cap unrecovered — suspicion blocks the advance.
    case unrecoveredRests
    /// Nothing decisive either way.
    case mixedSession

    // Ease evidence.
    case shortSets
    case loweredWeight
    case endedEarly
    case repeatedBackOffs

    /// The one quiet clause the journal shows after the change ("— clean session").
    public var summary: String {
        switch self {
        case .cleanSession: return "clean session"
        case .strongSession: return "fast recovery on every walk"
        case .snapToCapacity: return "ran well past the plan"
        case .bandTopped: return "topped the rep band"
        case .highEffort(let rating): return "felt all-out (effort \(rating))"
        case .unrecoveredRests: return "rests weren't recovering"
        case .mixedSession: return "mixed session"
        case .shortSets: return "sets came up short"
        case .loweredWeight: return "weight lowered mid-session"
        case .endedEarly: return "ended early"
        case .repeatedBackOffs: return "repeated back-offs"
        }
    }
}
