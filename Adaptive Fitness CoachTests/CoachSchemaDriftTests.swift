import Foundation
import Testing
import FoundationModels
import AdaptiveCore
@testable import Adaptive_Fitness_Coach

/// Pins the `@Generable` mirror DTOs to the RoutineExchange schema: a plan encoded from the
/// mirror must parse through the one test-pinned import path. If a field is renamed on either
/// side, this fails before the model ever does.
struct CoachSchemaDriftTests {

    @Test func mirrorSchemaMatchesExchange() throws {
        let plan = GenerablePlan(
            summary: "Two days to start.",
            routines: [
                GenerableRoutine(
                    name: "Strength A",
                    cards: [
                        GenerableCard(type: "exercise", exercise: "goblet_squat", reps: 8, weightLb: 20),
                        GenerableCard(type: "rest", seconds: 90, adaptive: true),
                        GenerableCard(type: "exercise", exercise: "plank", holdSeconds: 30),
                    ],
                    rounds: 3,
                    days: ["monday", "thursday"],
                    time: "07:30"
                ),
                GenerableRoutine(
                    name: "Easy Run",
                    cards: [GenerableCard(type: "run", minutes: 20, warmupMinutes: 5, cooldownMinutes: 5)]
                ),
            ]
        )

        let proposal = try CoachProposalValidator.validate(rawJSON: plan.exchangeJSON(), summary: plan.summary)

        #expect(proposal.droppedCardCount == 0)
        #expect(proposal.droppedRoutineCount == 0)
        #expect(proposal.routines.map(\.name) == ["Strength A", "Easy Run"])

        let strength = try #require(proposal.routines.first)
        #expect(strength.rounds == 3)
        #expect(strength.repeatDays == [.monday, .thursday])
        #expect(strength.scheduleTime == ScheduleTime(hour: 7, minute: 30))
        #expect(strength.cards.count == 3)
        let squat = try #require(strength.exerciseItems.first)
        #expect(squat.reps == 8)
        #expect(squat.seedWeight == .lb(20))

        let run = try #require(proposal.routines.last?.firstRunCard)
        #expect(run.durationMinutes == 20)
    }

    /// Building the tool's `GenerationSchema` exercises every `@Guide` constraint — a guide
    /// the framework rejects asserts here, in a unit test, not in a live session.
    @Test func proposePlanToolSchemaBuilds() {
        let tool = ProposePlanTool(onProposal: { _ in })
        _ = tool.parameters
        #expect(!tool.name.isEmpty)
    }

    /// A guided-decoding miss (should be impossible, but N6: never trust blindly) still can't
    /// reach the store — the validator drops it and counts it.
    @Test func invalidSlugFromMirrorIsStillDropped() throws {
        var card = GenerableCard(type: "exercise")
        card.exercise = "kettlebell_juggling"
        card.reps = 10
        let plan = GenerablePlan(summary: "", routines: [
            GenerableRoutine(name: "Odd", cards: [card, GenerableCard(type: "rest", seconds: 60)]),
        ])
        let proposal = try CoachProposalValidator.validate(rawJSON: plan.exchangeJSON())
        #expect(proposal.droppedCardCount == 1)
        #expect(proposal.routines.first?.cards.count == 1)
    }
}
