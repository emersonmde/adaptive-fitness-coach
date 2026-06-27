import Foundation

/// A real-time adjustment the engine made to the plan, in response to heart-rate zone.
public enum AdaptationAction: String, Codable, Sendable, Hashable {
    /// HR ran hot during a run → the run was ended early.
    case shortenedRun
    /// HR stayed comfortable through the planned run → the run was extended.
    case extendedRun
    /// HR had not recovered by the end of a walk → the walk was lengthened.
    case lengthenedWalk
    /// HR recovered quickly during a walk → the walk was ended early.
    case shortenedWalk

    /// Whether this action increases effort (the higher-risk direction, per the
    /// "bias toward backing off" constraint). Used only for documentation/analytics.
    public var increasesEffort: Bool {
        switch self {
        case .extendedRun, .shortenedWalk: true
        case .shortenedRun, .lengthenedWalk: false
        }
    }
}

/// A record of one adaptation, carrying the calm one-line copy shown on the watch (A4 / Q5).
///
/// `atSessionTime` is the elapsed session time (not a wall-clock `Date`) so the interval
/// engine stays fully deterministic and unit-testable without a clock.
public struct AdaptationEvent: Codable, Sendable, Hashable {
    public let action: AdaptationAction
    public let atSessionTime: TimeInterval
    public let zone: Int

    public init(action: AdaptationAction, atSessionTime: TimeInterval, zone: Int) {
        self.action = action
        self.atSessionTime = atSessionTime
        self.zone = zone
    }

    /// The single calm line surfaced in the adaptation banner. No "why", no nagging (Q5).
    public var message: String {
        switch action {
        case .shortenedRun: "Easing up — shortening this run"
        case .lengthenedWalk: "Taking it easy — extending your walk"
        case .extendedRun: "Feeling strong — keep running"
        case .shortenedWalk: "Recovered — back to running"
        }
    }
}
