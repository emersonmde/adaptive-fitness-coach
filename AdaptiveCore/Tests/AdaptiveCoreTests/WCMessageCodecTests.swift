import Foundation
import Testing
@testable import AdaptiveCore

struct WCMessageCodecTests {

    private func sampleRoutines() -> [Routine] {
        [
            Routine(name: "Morning Run", type: .adaptiveRun, repeatDays: [.tuesday, .friday],
                    scheduleTime: ScheduleTime(hour: 7, minute: 0), reminderEnabled: true),
            Routine(name: "Strength Circuit", type: .strength, repeatDays: [.monday, .wednesday],
                    scheduleTime: ScheduleTime(hour: 18, minute: 30), reminderEnabled: false),
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

    // MARK: - P1 (v2): strength routines

    @Test func roundTripsStrengthRoutineWithExercises() throws {
        let routines = [
            Routine(name: "Push Day", type: .strength, repeatDays: [.monday],
                    exercises: [
                        StrengthExerciseItem(exerciseId: "db_bench_press", sets: 3, reps: 10, seedWeight: .lb(15)),
                        StrengthExerciseItem(exerciseId: "plank", sets: 3, holdSeconds: 30),
                    ]),
        ]
        let message = try WCMessageCodec.encode(routines: routines)
        let decoded = try WCMessageCodec.decodeRoutines(from: message)
        #expect(decoded == routines)
        #expect(decoded.first?.exercises.count == 2)
    }

    /// A v1 payload from a not-yet-updated counterpart is rejected outright (the receiver keeps
    /// its last-known-good routines) rather than silently dropping the strength field.
    @Test func rejectsV1Payload() throws {
        let data = try JSONEncoder().encode(sampleRoutines())
        let message: [String: Any] = [WCMessageCodec.Key.routines: data, WCMessageCodec.Key.version: 1]
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(1)) {
            try WCMessageCodec.decodeRoutines(from: message)
        }
    }
}
