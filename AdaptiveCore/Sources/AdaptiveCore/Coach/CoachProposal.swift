import Foundation

/// A validated plan draft emitted by a coach engine: real `Routine` values that already passed
/// the exchange-schema validation (unknown movements dropped, values clamped, N6), plus an
/// honest account of what didn't survive so the UI can say "2 movements the app can't coach yet
/// were left out" instead of silently shrinking the plan.
public struct CoachProposal: Sendable, Hashable {
    /// The proposed routines, ready for the standard review → `RoutineStore.importRoutines`
    /// path (which grafts existing run progression back on — the pinned invariant).
    public var routines: [Routine]
    /// The coach's one-or-two-line description of the proposal, shown on the proposal card.
    public var summary: String
    /// Cards in the raw model output that validation dropped (unknown exercise ids/types).
    public var droppedCardCount: Int
    /// Whole routines dropped because no card survived.
    public var droppedRoutineCount: Int

    public init(
        routines: [Routine],
        summary: String = "",
        droppedCardCount: Int = 0,
        droppedRoutineCount: Int = 0
    ) {
        self.routines = routines
        self.summary = summary
        self.droppedCardCount = droppedCardCount
        self.droppedRoutineCount = droppedRoutineCount
    }
}

/// Funnels raw model output into the one test-pinned validation path. Every engine calls this
/// before emitting `CoachEvent.proposal`; nothing model-shaped reaches the UI or the store
/// without passing through `RoutineExchange`'s rules.
public enum CoachProposalValidator {
    /// Validate exchange-shaped JSON (tolerant of fences/prose, like the manual import path)
    /// into a proposal. Throws `RoutineExchange.ExchangeError` when nothing usable survives.
    public static func validate(rawJSON: String, summary: String = "") throws -> CoachProposal {
        let result = try RoutineExchange.importRoutinesDetailed(fromJSON: rawJSON)
        return CoachProposal(
            routines: result.routines,
            summary: summary,
            droppedCardCount: result.droppedCardCount,
            droppedRoutineCount: result.droppedRoutineCount
        )
    }
}
