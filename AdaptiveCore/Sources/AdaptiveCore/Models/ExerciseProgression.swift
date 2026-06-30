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
    /// When the adjustment was made (unused by latest-value apply; the seed for P2 history).
    public let date: Date

    public init(
        id: UUID = UUID(),
        exerciseId: String,
        weight: Weight? = nil,
        reps: Int? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.weight = weight
        self.reps = reps
        self.date = date
    }
}

/// One routine's worth of progressions — the unit that travels watch → phone over WatchConnectivity.
/// `routineId` is the routing key: the receiver applies the `updates` to the matching routine.
public struct ProgressionBatch: Codable, Sendable, Hashable {
    public let routineId: UUID
    public let updates: [ProgressionUpdate]

    public init(routineId: UUID, updates: [ProgressionUpdate]) {
        self.routineId = routineId
        self.updates = updates
    }
}
