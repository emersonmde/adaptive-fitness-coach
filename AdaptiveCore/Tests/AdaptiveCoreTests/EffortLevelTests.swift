import Foundation
import Testing
@testable import AdaptiveCore

struct EffortLevelTests {
    @Test func scoresAndLabels() {
        #expect(EffortLevel.easy.score == 2)
        #expect(EffortLevel.moderate.score == 5)
        #expect(EffortLevel.hard.score == 8)
        #expect(EffortLevel.allOut.score == 10)
        #expect(EffortLevel.allCases.map(\.label) == ["Easy", "Moderate", "Hard", "All-out"])
    }

    @Test func bucketEdges() {
        #expect(EffortLevel(score: 1) == .easy)
        #expect(EffortLevel(score: 3) == .easy)
        #expect(EffortLevel(score: 4) == .moderate)
        #expect(EffortLevel(score: 6) == .moderate)
        #expect(EffortLevel(score: 7) == .hard)
        #expect(EffortLevel(score: 8) == .hard)
        #expect(EffortLevel(score: 9) == .allOut)
        #expect(EffortLevel(score: 10) == .allOut)
        #expect(EffortLevel(score: 0) == nil)
        #expect(EffortLevel(score: 11) == nil)
    }

    @Test func roundTripsThroughItsOwnScore() {
        for level in EffortLevel.allCases {
            #expect(EffortLevel(score: level.score) == level)
        }
    }

    @Test func stepping() {
        #expect(EffortLevel.easy.up == .moderate)
        #expect(EffortLevel.allOut.up == nil)
        #expect(EffortLevel.easy.down == nil)
        #expect(EffortLevel.hard.down == .moderate)
    }

    /// USER DECISION (P6.1): Hard and All-out both hold progression. Both policies gate on
    /// `highEffortThreshold` — this pin makes a future threshold tweak fail loudly instead of
    /// silently un-holding "Hard" sessions.
    @Test func hardAndAllOutSitAtOrAboveTheHoldThreshold() {
        #expect(EffortLevel.hard.score >= RunProgressionPolicy().highEffortThreshold)
        #expect(EffortLevel.allOut.score >= RunProgressionPolicy().highEffortThreshold)
        #expect(EffortLevel.hard.score >= StrengthProgressionConfig().highEffortThreshold)
        #expect(EffortLevel.moderate.score < RunProgressionPolicy().highEffortThreshold)
        #expect(EffortLevel.moderate.score < StrengthProgressionConfig().highEffortThreshold)
    }
}
