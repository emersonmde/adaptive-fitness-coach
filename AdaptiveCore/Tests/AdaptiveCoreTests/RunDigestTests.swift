import Foundation
import Testing
@testable import AdaptiveCore

struct RunDigestTests {
    private var sample: RunDigest {
        RunDigest(
            routineId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB"),
            runSeconds: 732, walkSeconds: 448,
            runIntervals: 6, walkIntervals: 5,
            longestRunSeconds: 210, timeInTargetZoneSeconds: 511,
            meanRecoveryDrop: 23.4, backOffs: 1, fastRecoveries: 2
        )
    }

    @Test func roundTripsThroughMetadata() throws {
        let decoded = try #require(RunDigest(metadata: sample.metadata()))
        #expect(decoded == sample)
    }

    @Test func nilFieldsAreOmittedNeverFabricated() throws {
        var digest = sample
        digest.routineId = nil
        digest.meanRecoveryDrop = nil
        let metadata = digest.metadata()
        #expect(metadata[RunDigest.Key.routineID] == nil)
        #expect(metadata[RunDigest.Key.meanRecoveryDrop] == nil)
        let decoded = try #require(RunDigest(metadata: metadata))
        #expect(decoded.routineId == nil)
        #expect(decoded.meanRecoveryDrop == nil)   // a gap stays a gap (N6)
    }

    @Test func unknownVersionOrMissingVersionDecodesAsNoDigest() {
        var metadata = sample.metadata()
        metadata[RunDigest.Key.version] = "999"
        #expect(RunDigest(metadata: metadata) == nil)
        metadata[RunDigest.Key.version] = nil
        #expect(RunDigest(metadata: metadata) == nil)
        #expect(RunDigest(metadata: [:]) == nil)   // non-digest workouts read as "no digest"
    }

    @Test func garbageValuesDecodeAsAbsentNotInvented() throws {
        var metadata = sample.metadata()
        metadata[RunDigest.Key.runSeconds] = "not a number"
        metadata[RunDigest.Key.routineID] = "not a uuid"
        let decoded = try #require(RunDigest(metadata: metadata))
        #expect(decoded.runSeconds == 0)
        #expect(decoded.routineId == nil)
        #expect(decoded.walkSeconds == sample.walkSeconds)   // the rest still decode
    }

    @Test func buildsFromSessionSummary() {
        let summary = SessionSummary(
            totalDuration: 1500,
            totalRunDuration: 732, totalWalkDuration: 448,
            intervalsCompleted: 6,
            runBackOffCount: 1,
            fastRecoveries: 2,
            walksCompleted: 5,
            timeInTargetZone: 511,
            longestRunSeconds: 210,
            meanRecoveryDrop: 23.4
        )
        let routineId = UUID()
        let digest = RunDigest(summary: summary, routineId: routineId)
        #expect(digest == RunDigest(
            routineId: routineId, runSeconds: 732, walkSeconds: 448,
            runIntervals: 6, walkIntervals: 5,
            longestRunSeconds: 210, timeInTargetZoneSeconds: 511,
            meanRecoveryDrop: 23.4, backOffs: 1, fastRecoveries: 2
        ))
    }

    @Test func runFractionIsHonest() {
        #expect(sample.runFraction.map { abs($0 - 732.0 / 1180.0) < 0.0001 } == true)
        #expect(RunDigest().runFraction == nil)   // no interval time → no percentage
    }
}
