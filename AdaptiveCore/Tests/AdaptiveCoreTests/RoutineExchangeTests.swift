import Foundation
import Testing
@testable import AdaptiveCore

struct RoutineExchangeTests {

    private func sample() -> [Routine] {
        [
            Routine(name: "Morning Run", repeatDays: [.tuesday, .friday],
                    scheduleTime: ScheduleTime(hour: 7, minute: 0),
                    cards: [.run(RunCard(durationMinutes: 30))]),
            Routine(name: "Push Day", repeatDays: [.monday, .wednesday],
                    scheduleTime: ScheduleTime(hour: 18, minute: 30),
                    cards: [
                        .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
                        .rest(RestCard(seconds: 60)),
                        .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)),
                    ],
                    rounds: 3),
        ]
    }

    /// Export → import → export reproduces the same JSON (export omits ids, so this is the fidelity
    /// invariant even though import mints fresh ids).
    @Test func roundTripsThroughJSON() throws {
        let original = sample()
        let json = RoutineExchange.exportJSON(original)
        let imported = try RoutineExchange.importRoutines(fromJSON: json)
        #expect(RoutineExchange.exportJSON(imported) == json)
    }

    @Test func importPreservesNamesDaysTimeRounds() throws {
        let imported = try RoutineExchange.importRoutines(fromJSON: RoutineExchange.exportJSON(sample()))
        let push = try #require(imported.first { $0.name == "Push Day" })
        #expect(push.repeatDays == [.monday, .wednesday])
        #expect(push.scheduleTime == ScheduleTime(hour: 18, minute: 30))
        #expect(push.rounds == 3)
        #expect(push.exerciseItems.count == 2)
    }

    @Test func toleratesCodeFencesAndChatter() throws {
        let json = RoutineExchange.exportJSON(sample())
        let wrapped = "Sure! Here's your updated set:\n\n```json\n\(json)\n```\n\nLet me know!"
        let imported = try RoutineExchange.importRoutines(fromJSON: wrapped)
        #expect(imported.count == 2)
    }

    @Test func dropsUnknownExerciseIds() throws {
        let json = """
        {"schema":"adaptive-fitness-coach/routines","version":1,"routines":[
          {"name":"Bad","cards":[
            {"type":"exercise","exercise":"not_a_real_move","reps":10},
            {"type":"exercise","exercise":"goblet_squat","reps":8}
          ]}
        ]}
        """
        let imported = try RoutineExchange.importRoutines(fromJSON: json)
        let routine = try #require(imported.first)
        #expect(routine.exerciseItems.count == 1)
        #expect(routine.exerciseItems.first?.exerciseId == "goblet_squat")
    }

    @Test func neverFabricatesLoadOrReps() throws {
        // A bodyweight move given a weight, and a hold given reps — both ignored (N6).
        let json = """
        {"schema":"adaptive-fitness-coach/routines","version":1,"routines":[
          {"name":"Edge","cards":[
            {"type":"exercise","exercise":"push_up","reps":12,"weightLb":45},
            {"type":"exercise","exercise":"plank","reps":20,"holdSeconds":40}
          ]}
        ]}
        """
        let routine = try #require(try RoutineExchange.importRoutines(fromJSON: json).first)
        let pushUp = try #require(routine.exerciseItems.first { $0.exerciseId == "push_up" })
        #expect(pushUp.seedWeight == nil)       // stays bodyweight
        #expect(pushUp.reps == 12)
        let plank = try #require(routine.exerciseItems.first { $0.exerciseId == "plank" })
        #expect(plank.reps == nil)              // stays a hold
        #expect(plank.holdSeconds == 40)
    }

    @Test func toleratesBareArray() throws {
        let json = """
        [{"name":"Bare","cards":[{"type":"run","minutes":20}]}]
        """
        let imported = try RoutineExchange.importRoutines(fromJSON: json)
        #expect(imported.first?.firstRunCard?.durationMinutes == 20)
    }

    @Test func rejectsNonJSON() {
        #expect(throws: RoutineExchange.ExchangeError.notJSON) {
            try RoutineExchange.importRoutines(fromJSON: "no json here")
        }
    }

    @Test func rejectsUnrecognizedSchema() {
        let json = #"{"schema":"some-other-app","version":1,"routines":[{"name":"X","cards":[{"type":"run","minutes":10}]}]}"#
        #expect(throws: RoutineExchange.ExchangeError.unrecognizedSchema) {
            try RoutineExchange.importRoutines(fromJSON: json)
        }
    }

    @Test func malformedFieldInOurEnvelopeIsNotCalledNotJSON() {
        // Build 11 pin: schema matched but "minutes" is a string — the user pasted real
        // JSON in our format; the error must say what's wrong, not "isn't JSON".
        let json = #"{"schema":"\#(RoutineExchange.schemaName)","version":1,"routines":[{"name":"X","cards":[{"type":"run","minutes":"20"}]}]}"#
        do {
            _ = try RoutineExchange.importRoutines(fromJSON: json)
            Issue.record("should have thrown")
        } catch let RoutineExchange.ExchangeError.malformedRoutines(detail) {
            #expect(detail.contains("minutes"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func rejectsEmptyAfterDropping() {
        // Only an unknown exercise → its routine drops → no routines.
        let json = #"{"schema":"adaptive-fitness-coach/routines","version":1,"routines":[{"name":"X","cards":[{"type":"exercise","exercise":"ghost"}]}]}"#
        #expect(throws: RoutineExchange.ExchangeError.noRoutines) {
            try RoutineExchange.importRoutines(fromJSON: json)
        }
    }

    @Test func primingPromptCarriesSchemaVocabAndJSON() {
        let prompt = RoutineExchange.primingPrompt(sample())
        #expect(prompt.contains(RoutineExchange.schemaName))
        #expect(prompt.contains("goblet_squat"))   // vocab listing
        #expect(prompt.contains("\"Push Day\"") || prompt.contains("Push Day"))
        #expect(prompt.contains("```json"))
    }

    @Test func markdownSummarizes() {
        let md = RoutineExchange.markdown(sample())
        #expect(md.contains("## Push Day"))
        #expect(md.contains("Dumbbell Bench Press"))
    }

    @Test func rejectsNewerSchemaVersion() {
        let json = #"{"schema":"adaptive-fitness-coach/routines","version":7,"routines":[{"name":"R","cards":[{"type":"run","minutes":20}]}]}"#
        #expect(throws: RoutineExchange.ExchangeError.unsupportedVersion(7)) {
            try RoutineExchange.importRoutines(fromJSON: json)
        }
    }

    @Test func fencedPayloadWinsOverEarlierBracketsInProse() throws {
        // Chatter containing brackets before the fence must not sink the import.
        let text = """
        Here's [1] your updated plan (see notes {above}):
        ```json
        {"schema":"adaptive-fitness-coach/routines","version":1,"routines":[{"name":"Tempo","cards":[{"type":"run","minutes":25}]}]}
        ```
        """
        let routines = try RoutineExchange.importRoutines(fromJSON: text)
        #expect(routines.first?.name == "Tempo")
        #expect(routines.first?.firstRunCard?.durationMinutes == 25)
    }

    @Test func garbageScheduleTimeIsRejectedNotClamped() throws {
        let json = #"{"schema":"adaptive-fitness-coach/routines","version":1,"routines":[{"name":"R","time":"99:99","cards":[{"type":"run","minutes":20}]}]}"#
        let routines = try RoutineExchange.importRoutines(fromJSON: json)
        #expect(routines.first?.scheduleTime == nil)
    }
}
