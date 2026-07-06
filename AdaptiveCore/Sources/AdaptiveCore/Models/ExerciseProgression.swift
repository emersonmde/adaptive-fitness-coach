import Foundation

/// A recorded change to an exercise's seed prescription — the user bumped a weight or rep count
/// (typically on the watch, because the seed felt easy) and it should stick for next time.
///
/// P1 records the **latest value only** (it overwrites the routine's seed; there is no history
/// log yet), but the type deliberately carries everything a P2 progression history would need:
/// the `exerciseId` it applies to, the new `weight`/`reps`, and the `date` it was made. A future
/// P2 history is then "append `ProgressionUpdate` rows keyed by `exerciseId`" with no reshaping.
///
/// **`nil` means "no change", not "clear to bodyweight".** `weight == nil` leaves the load
/// untouched (e.g. a reps-only bump), and `reps == nil` leaves reps untouched (e.g. a hold, or a
/// weight-only bump). Because a watch adjustment can only nudge a dimension that already exists,
/// a progression never *produces* a bodyweight/hold value, so collapsing "nil = no change" with
/// "nil = bodyweight" is safe — but the apply logic still guards on the card's existing shape so a
/// progression can never turn a bodyweight card into a weighted one (N6: never fabricate a signal).
public struct ProgressionUpdate: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// The `ExerciseLibrary` slug this applies to — the only exercise id that crosses WatchConnectivity.
    public let exerciseId: String
    /// New seed load, or `nil` to leave the existing weight unchanged.
    public let weight: Weight?
    /// New seed reps, or `nil` to leave the existing reps unchanged.
    public let reps: Int?
    /// New seed hold duration, or `nil` to leave the existing hold unchanged (P2 — hold
    /// progression). Shape-guarded on apply like the others: never turns a rep card into a hold.
    public let holdSeconds: TimeInterval?
    /// When the adjustment was made (unused by latest-value apply; the seed for history).
    public let date: Date
    /// Why the policy moved this seed, as a rendered clause ("clean session") — P6's journal
    /// line. A string on the wire deliberately: new reason variants can never break the
    /// codec's exact-version decode. nil for manual adjustments and pre-v4 senders.
    public let reason: String?

    public init(
        id: UUID = UUID(),
        exerciseId: String,
        weight: Weight? = nil,
        reps: Int? = nil,
        holdSeconds: TimeInterval? = nil,
        date: Date = Date(),
        reason: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.weight = weight
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.date = date
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey { case id, exerciseId, weight, reps, holdSeconds, date, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        weight = try c.decodeIfPresent(Weight.self, forKey: .weight)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        holdSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .holdSeconds)
        date = try c.decode(Date.self, forKey: .date)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// A recorded change to a run card's interval seeds — the session outcome moved the run/walk
/// durations (see `RunProgressionPolicy`) and the new values should stick for next time.
///
/// Latest-value-only, like `ProgressionUpdate` (P1); `date` is carried for a future P2 history.
/// Routing is by the run card's `id` (stable across sync, unlike anything derived).
public struct RunProgressionUpdate: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// The `RunCard.id` this applies to.
    public let cardId: UUID
    /// New seed run-interval length, seconds.
    public let runSeconds: Int
    /// New seed walk-interval length, seconds.
    public let walkSeconds: Int
    /// When the session that produced this ended.
    public let date: Date
    /// Why the seeds moved, as a rendered clause (see `ProgressionUpdate.reason`).
    public let reason: String?
    /// The run block's planned length when this was authored — lets the phone render
    /// "continuous" honestly (seed ≥ block) without re-deriving the plan. nil pre-v4.
    public let blockSeconds: Int?

    public init(
        id: UUID = UUID(),
        cardId: UUID,
        runSeconds: Int,
        walkSeconds: Int,
        date: Date = Date(),
        reason: String? = nil,
        blockSeconds: Int? = nil
    ) {
        self.id = id
        self.cardId = cardId
        self.runSeconds = runSeconds
        self.walkSeconds = walkSeconds
        self.date = date
        self.reason = reason
        self.blockSeconds = blockSeconds
    }
}

/// One routine's worth of progressions — the unit that travels watch → phone over WatchConnectivity.
/// `routineId` is the routing key: the receiver applies the updates to the matching routine.
/// Strength (`updates`) and run (`runUpdates`) progressions share the batch so one workout's
/// results travel as one message.
///
/// v4 splits the batch into two lanes: `updates`/`runUpdates` are **applied** micro-steps
/// (the watch already applied them locally; the phone applies on receipt, as always), while
/// `proposals`/`runProposals` are **structural moves awaiting the user's confirm** — a load
/// step-up or a run-shape graduation. The watch never applies a proposal; the phone stashes
/// it for the confirm card and only a confirm sends it through `applyProgressions`.
public struct ProgressionBatch: Codable, Sendable, Hashable {
    public let routineId: UUID
    public let updates: [ProgressionUpdate]
    public let runUpdates: [RunProgressionUpdate]
    /// Structural strength moves (band-topped load steps) awaiting confirmation.
    public let proposals: [ProgressionUpdate]
    /// Structural run-shape moves (walk shrink / continuous graduation) awaiting confirmation.
    public let runProposals: [RunProgressionUpdate]
    /// The session's post-workout effort rating (1–10) — journal context; the only channel
    /// effort crosses to the phone.
    public let perceivedEffort: Int?
    /// When the session that produced this batch ended.
    public let sessionDate: Date?

    public init(
        routineId: UUID,
        updates: [ProgressionUpdate] = [],
        runUpdates: [RunProgressionUpdate] = [],
        proposals: [ProgressionUpdate] = [],
        runProposals: [RunProgressionUpdate] = [],
        perceivedEffort: Int? = nil,
        sessionDate: Date? = nil
    ) {
        self.routineId = routineId
        self.updates = updates
        self.runUpdates = runUpdates
        self.proposals = proposals
        self.runProposals = runProposals
        self.perceivedEffort = perceivedEffort
        self.sessionDate = sessionDate
    }

    private enum CodingKeys: String, CodingKey {
        case routineId, updates, runUpdates, proposals, runProposals, perceivedEffort, sessionDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routineId = try c.decode(UUID.self, forKey: .routineId)
        updates = try c.decodeIfPresent([ProgressionUpdate].self, forKey: .updates) ?? []
        runUpdates = try c.decodeIfPresent([RunProgressionUpdate].self, forKey: .runUpdates) ?? []
        proposals = try c.decodeIfPresent([ProgressionUpdate].self, forKey: .proposals) ?? []
        runProposals = try c.decodeIfPresent([RunProgressionUpdate].self, forKey: .runProposals) ?? []
        perceivedEffort = try c.decodeIfPresent(Int.self, forKey: .perceivedEffort)
        sessionDate = try c.decodeIfPresent(Date.self, forKey: .sessionDate)
    }
}
