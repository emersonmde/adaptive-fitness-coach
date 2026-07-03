import Foundation
import Testing
@testable import AdaptiveCore

/// The provider-agnostic coach pieces: instructions, context, and the validation funnel every
/// engine's raw output must pass through before the UI sees a proposal.
struct CoachPromptBuilderTests {

    @Test func instructionsContainFullVocabulary() {
        let instructions = CoachPromptBuilder.instructions(intent: .buildNewPlan, context: .empty)
        for exercise in ExerciseLibrary.all {
            #expect(instructions.contains(exercise.id), "vocabulary is missing \(exercise.id)")
        }
    }

    @Test func vocabularyGroupsByEquipment() {
        let vocab = CoachPromptBuilder.vocabulary(ExerciseLibrary.all)
        #expect(vocab.contains(Equipment.barbell.displayName))
        #expect(vocab.contains(Equipment.bodyweight.displayName))
        // Combined-gear movements are labeled with all of it.
        #expect(vocab.contains("Barbell + Bench") || vocab.contains("Bench + Barbell"))
    }

    @Test func buildNewPlanAsksForIntake() {
        let instructions = CoachPromptBuilder.instructions(intent: .buildNewPlan, context: .empty)
        #expect(instructions.contains("equipment"))
        #expect(instructions.contains("goal"))
        #expect(!instructions.contains("shown below"))   // no routines JSON in a fresh build
    }

    @Test func reviseEmbedsRoutinesAndNameStability() {
        let routine = Routine(name: "Push Day", cards: [
            .exercise(StrengthExerciseItem(exerciseId: "push_up", reps: 10)),
        ])
        let context = CoachContextBuilder.context(for: .reviseRoutine(routine.id), routines: [routine])
        let instructions = CoachPromptBuilder.instructions(intent: .reviseRoutine(routine.id), context: context)
        #expect(instructions.contains("\"Push Day\""))
        #expect(instructions.contains("push_up"))               // the exported JSON is embedded
        #expect(instructions.contains("name"))
        #expect(instructions.contains("exactly the same"))      // the graft-preserving rule
    }

    @Test func schemaRulesMatchTheExchangeSpec() {
        // The card semantics the coach is taught must be the ones the importer enforces —
        // the priming prompt is the tested spec, so the key rule phrases must agree.
        for phrase in ["\"run\", \"exercise\", or \"rest\"", "holdSeconds", "rounds", "HH:mm"] {
            #expect(CoachPromptBuilder.instructions(intent: .buildNewPlan, context: .empty).contains(phrase))
        }
    }
}

struct CoachContextBuilderTests {

    private func calibratedRunRoutine() -> Routine {
        var run = RunCard(durationMinutes: 20)
        run.runSeconds = 180
        run.walkSeconds = 60
        run.seedsCalibrated = true
        return Routine(name: "Morning Run", cards: [.run(run)])
    }

    @Test func progressionSummaryShowsEarnedState() throws {
        let strength = Routine(name: "Strength", cards: [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 12, seedWeight: .lb(25))),
            .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 45)),
            .rest(RestCard(seconds: 60)),
        ])
        let summary = try #require(CoachContextBuilder.progressionSummary([calibratedRunRoutine(), strength]))
        #expect(summary.contains("180s run / 60s walk"))
        #expect(summary.contains("earned from real sessions"))
        #expect(summary.contains("Goblet Squat: 12 reps"))
        #expect(summary.contains("Plank: 45s hold"))
        #expect(!summary.contains("Rest"))   // rests aren't progression state
    }

    @Test func uncalibratedRunIsLabeledHonestly() throws {
        let routine = Routine(name: "New Run", cards: [.run(RunCard())])
        let summary = try #require(CoachContextBuilder.progressionSummary([routine]))
        #expect(summary.contains("not yet calibrated"))
    }

    @Test func buildNewPlanContextCarriesOnlyExistingNames() {
        let context = CoachContextBuilder.context(for: .buildNewPlan, routines: [calibratedRunRoutine()])
        #expect(context.routinesJSON == nil)
        #expect(context.focusRoutineName == nil)
        #expect(context.progressionSummary?.contains("Morning Run") == true)
    }

    @Test func reviseRoutineContextFocusesOneRoutine() {
        let target = calibratedRunRoutine()
        let other = Routine(name: "Other", cards: [.run(RunCard())])
        let context = CoachContextBuilder.context(for: .reviseRoutine(target.id), routines: [other, target])
        #expect(context.focusRoutineName == "Morning Run")
        #expect(context.routinesJSON?.contains("Morning Run") == true)
        #expect(context.routinesJSON?.contains("Other") != true)
    }

    @Test func reviseUnknownRoutineFallsBackToEmpty() {
        let context = CoachContextBuilder.context(for: .reviseRoutine(UUID()), routines: [])
        #expect(context == .empty)
    }
}

struct CoachProposalValidatorTests {

    private func exchangeJSON(cards: String) -> String {
        """
        {"schema": "adaptive-fitness-coach/routines", "version": 1, "routines": [
            {"name": "Test", "cards": [\(cards)]}
        ]}
        """
    }

    @Test func validJSONBecomesProposal() throws {
        let proposal = try CoachProposalValidator.validate(
            rawJSON: exchangeJSON(cards: #"{"type": "exercise", "exercise": "push_up", "reps": 12}"#),
            summary: "A start."
        )
        #expect(proposal.routines.count == 1)
        #expect(proposal.summary == "A start.")
        #expect(proposal.droppedCardCount == 0)
        #expect(proposal.droppedRoutineCount == 0)
    }

    @Test func unknownMovementsAreDroppedAndCounted() throws {
        let proposal = try CoachProposalValidator.validate(rawJSON: exchangeJSON(cards: """
            {"type": "exercise", "exercise": "push_up", "reps": 12},
            {"type": "exercise", "exercise": "bulgarian_split_squat_from_mars", "reps": 8},
            {"type": "wormhole"}
        """))
        #expect(proposal.routines.first?.cards.count == 1)
        #expect(proposal.droppedCardCount == 2)
    }

    @Test func routineWithNoSurvivingCardsIsDroppedAndCounted() throws {
        let json = """
        {"schema": "adaptive-fitness-coach/routines", "version": 1, "routines": [
            {"name": "Good", "cards": [{"type": "rest", "seconds": 60}]},
            {"name": "All Invalid", "cards": [{"type": "exercise", "exercise": "made_up"}]}
        ]}
        """
        let proposal = try CoachProposalValidator.validate(rawJSON: json)
        #expect(proposal.routines.map(\.name) == ["Good"])
        #expect(proposal.droppedRoutineCount == 1)
        #expect(proposal.droppedCardCount == 1)
    }

    @Test func garbageThrows() {
        #expect(throws: RoutineExchange.ExchangeError.notJSON) {
            try CoachProposalValidator.validate(rawJSON: "I would suggest some squats, my friend.")
        }
    }

    @Test func nothingUsableThrows() {
        #expect(throws: RoutineExchange.ExchangeError.noRoutines) {
            try CoachProposalValidator.validate(
                rawJSON: exchangeJSON(cards: #"{"type": "exercise", "exercise": "made_up"}"#)
            )
        }
    }

    @Test func toleratesModelProseAndFences() throws {
        let wrapped = """
        Here's your plan!

        ```json
        \(exchangeJSON(cards: #"{"type": "run", "minutes": 20}"#))
        ```

        Let me know how it feels.
        """
        let proposal = try CoachProposalValidator.validate(rawJSON: wrapped)
        #expect(proposal.routines.first?.hasRun == true)
    }
}
