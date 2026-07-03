import Foundation
import FoundationModels
import AdaptiveCore

/// The `@Generable` mirror of the RoutineExchange schema — what the model actually emits when
/// it proposes a plan (via `ProposePlanTool`).
///
/// Deliberately a mirror, not the exchange DTOs themselves: the `@Generable` macro must be
/// attached in a FoundationModels-importing target, and AdaptiveCore stays Foundation-only.
/// Field names match the exchange schema exactly so conversion is plain `JSONEncoder` output
/// wrapped in the schema envelope, and every proposal still passes through the one test-pinned
/// validation path (`CoachProposalValidator` → `RoutineExchange.importRoutines`). Guided
/// decoding makes invalid slugs rare; the validator keeps them impossible (N6).
/// `CoachAppTests.mirrorSchemaMatchesExchange` pins the two schemas together.
@Generable
struct GenerablePlan: Encodable {
    @Guide(description: "One or two sentences describing the plan and why it fits the user.")
    var summary: String
    @Guide(description: "The complete set of proposed routines. When editing an existing routine, keep its name exactly the same.")
    var routines: [GenerableRoutine]
}

@Generable
struct GenerableRoutine: Encodable {
    @Guide(description: "The routine's display name. Keep stable when editing an existing routine.")
    var name: String
    @Guide(description: "Ordered workout cards. Put a rest card between exercises and one at the end for between rounds.")
    var cards: [GenerableCard]
    @Guide(description: "How many times the whole card list repeats — this is how sets work.", .range(1...6))
    var rounds: Int?
    @Guide(description: "Lowercase full weekday names, e.g. monday.")
    var days: [String]?
    @Guide(description: "Scheduled time of day, 24-hour HH:mm.")
    var time: String?
}

@Generable
struct GenerableCard: Encodable {
    @Guide(description: "The card kind.", .anyOf(["run", "exercise", "rest"]))
    var type: String
    @Guide(description: "Run cards only: adaptive run block length in minutes.", .range(5...120))
    var minutes: Int?
    @Guide(description: "Run cards only: walking warmup minutes (default 5).", .range(0...15))
    var warmupMinutes: Int?
    @Guide(description: "Run cards only: walking cooldown minutes (default 5).", .range(0...15))
    var cooldownMinutes: Int?
    @Guide(description: "Exercise cards only: the movement id from the vocabulary in your instructions.", .anyOf(ExerciseLibrary.all.map(\.id)))
    var exercise: String?
    @Guide(description: "Exercise cards only: target reps for rep-based movements.", .range(1...50))
    var reps: Int?
    @Guide(description: "Exercise cards only: starting load in pounds for weighted movements.")
    var weightLb: Double?
    @Guide(description: "Exercise cards only: hold duration in seconds for isometric holds.")
    var holdSeconds: Double?
    @Guide(description: "Rest cards only: rest length in seconds.")
    var seconds: Double?
    @Guide(description: "Rest cards only: true (default) lets heart-rate recovery end the rest early.")
    var adaptive: Bool?
}

extension GenerablePlan {
    /// The plan as exchange-envelope JSON — the wire format the pinned import path validates.
    func exchangeJSON() throws -> String {
        struct Envelope: Encodable {
            let schema = RoutineExchange.schemaName
            let version = RoutineExchange.schemaVersion
            let routines: [GenerableRoutine]
        }
        let data = try JSONEncoder().encode(Envelope(routines: routines))
        return String(decoding: data, as: UTF8.self)
    }
}
