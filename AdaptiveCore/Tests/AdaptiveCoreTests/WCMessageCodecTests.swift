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
}
