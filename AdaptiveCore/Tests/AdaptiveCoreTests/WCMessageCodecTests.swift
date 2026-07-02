import Foundation
import Testing
@testable import AdaptiveCore

struct WCMessageCodecTests {

    private func sampleRoutines() -> [Routine] {
        [
            Routine(name: "Morning Run", repeatDays: [.tuesday, .friday],
                    scheduleTime: ScheduleTime(hour: 7, minute: 0), reminderEnabled: true,
                    cards: [.run(RunCard(durationMinutes: 30))]),
            Routine(name: "Strength Circuit", repeatDays: [.monday, .wednesday],
                    scheduleTime: ScheduleTime(hour: 18, minute: 30), reminderEnabled: false,
                    cards: [.exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
                            .rest(RestCard(seconds: 30))],
                    rounds: 3),
        ]
    }

    @Test func roundTripsRoutines() throws {
        let routines = sampleRoutines()
        let message = try WCMessageCodec.encode(routines: routines)
        let decoded = try WCMessageCodec.decodeRoutines(from: message)
        #expect(decoded == routines)
    }

    @Test func encodesVersionField() throws {
        let message = try WCMessageCodec.encode(routines: [])
        #expect(message[WCMessageCodec.Key.version] as? Int == WCMessageCodec.currentVersion)
    }

    @Test func roundTripsEmptyArray() throws {
        let message = try WCMessageCodec.encode(routines: [])
        let decoded = try WCMessageCodec.decodeRoutines(from: message)
        #expect(decoded.isEmpty)
    }

    @Test func missingRoutinesThrows() {
        let message: [String: Any] = [WCMessageCodec.Key.version: WCMessageCodec.currentVersion]
        #expect(throws: WCMessageCodec.CodecError.missingRoutines) {
            try WCMessageCodec.decodeRoutines(from: message)
        }
    }

    @Test func unsupportedVersionThrows() throws {
        var message = try WCMessageCodec.encode(routines: sampleRoutines())
        message[WCMessageCodec.Key.version] = 99
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(99)) {
            try WCMessageCodec.decodeRoutines(from: message)
        }
    }

    @Test func missingVersionThrows() throws {
        let routines = sampleRoutines()
        let data = try JSONEncoder().encode(routines)
        let message: [String: Any] = [WCMessageCodec.Key.routines: data] // no version
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(0)) {
            try WCMessageCodec.decodeRoutines(from: message)
        }
    }

    // MARK: - v3: card-based routines

    @Test func roundTripsCardRoutine() throws {
        let routines = [
            Routine(name: "Push Day", repeatDays: [.monday],
                    cards: [
                        .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
                        .rest(RestCard(seconds: 60)),
                        .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)),
                    ],
                    rounds: 3),
        ]
        let message = try WCMessageCodec.encode(routines: routines)
        let decoded = try WCMessageCodec.decodeRoutines(from: message)
        #expect(decoded == routines)
        #expect(decoded.first?.exerciseItems.count == 2)
        #expect(decoded.first?.rounds == 3)
    }

    /// An older payload (v2) from a not-yet-updated counterpart is rejected outright — the
    /// receiver keeps its last-known-good routines rather than mis-decoding the new card shape.
    @Test func rejectsOlderVersionPayload() throws {
        let data = try JSONEncoder().encode(sampleRoutines())
        let message: [String: Any] = [WCMessageCodec.Key.routines: data, WCMessageCodec.Key.version: 2]
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(2)) {
            try WCMessageCodec.decodeRoutines(from: message)
        }
    }

    // MARK: - Progression channel (watch → phone)

    private func sampleBatch() -> ProgressionBatch {
        ProgressionBatch(routineId: UUID(), updates: [
            ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30), reps: 12),
            ProgressionUpdate(exerciseId: "plank", reps: nil), // hold: reps stays nil
        ])
    }

    @Test func roundTripsProgression() throws {
        let batch = sampleBatch()
        let message = try WCMessageCodec.encode(progression: batch)
        let decoded = try WCMessageCodec.decodeProgression(from: message)
        #expect(decoded == batch)
        #expect(message[WCMessageCodec.Key.progressionVersion] as? Int == WCMessageCodec.currentProgressionVersion)
    }

    @Test func missingProgressionThrows() {
        let message: [String: Any] = [WCMessageCodec.Key.progressionVersion: WCMessageCodec.currentProgressionVersion]
        #expect(throws: WCMessageCodec.CodecError.missingProgression) {
            try WCMessageCodec.decodeProgression(from: message)
        }
    }

    @Test func unsupportedProgressionVersionThrows() throws {
        var message = try WCMessageCodec.encode(progression: sampleBatch())
        message[WCMessageCodec.Key.progressionVersion] = 99
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(99)) {
            try WCMessageCodec.decodeProgression(from: message)
        }
    }

    /// The two channels are isolated: a routines payload must not decode as a progression, and a
    /// progression payload must not decode as routines (they key on different fields entirely).
    @Test func channelsAreIsolated() throws {
        let routinesMsg = try WCMessageCodec.encode(routines: sampleRoutines())
        #expect(throws: WCMessageCodec.CodecError.self) {
            try WCMessageCodec.decodeProgression(from: routinesMsg)
        }

        let progressionMsg = try WCMessageCodec.encode(progression: sampleBatch())
        #expect(throws: WCMessageCodec.CodecError.self) {
            try WCMessageCodec.decodeRoutines(from: progressionMsg)
        }
    }
}
