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
}
