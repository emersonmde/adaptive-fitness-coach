import Foundation
import Testing
@testable import AdaptiveCore

// MARK: - EffortPredictor (HR-derived suggestion for the post-run rating)

struct EffortPredictionTests {

    private func summary(
        runTime: TimeInterval = 600,
        inZone: TimeInterval = 400, aboveZone: TimeInterval = 0,
        backOffs: Int = 0, capped: Int = 0, defied: Int = 0,
        planned: Int = 6, completed: Int = 6,
        walksCompleted: Int = 5, fastRecoveries: Int = 0,
        meanDrop: Double? = nil, endedEarly: Bool = false
    ) -> SessionSummary {
        SessionSummary(
            totalDuration: 1800, totalRunDuration: runTime,
            intervalsCompleted: completed, plannedRunIntervals: planned,
            runBackOffCount: backOffs, walksHitCap: capped, walksDefied: defied,
            fastRecoveries: fastRecoveries, walksCompleted: walksCompleted,
            timeInTargetZone: inZone, timeAboveTargetZone: aboveZone,
            meanRecoveryDrop: meanDrop, endedEarly: endedEarly
        )
    }

    @Test func signalBlindSessionSuggestsNothing() {
        // No zone dwell, no recovery measurement: a prefill would fabricate a signal (N6).
        let blind = summary(inZone: 0, aboveZone: 0, meanDrop: nil)
        #expect(EffortPredictor.suggestedLevel(from: blind) == nil)
    }

    @Test func recoveryDataAloneIsEnoughSignal() {
        let hrOnly = summary(inZone: 0, aboveZone: 0, meanDrop: 22)
        #expect(EffortPredictor.suggestedLevel(from: hrOnly) != nil)
    }

    @Test func bailingWithBackOffsSuggestsAllOut() {
        let bailed = summary(backOffs: 1, completed: 2, endedEarly: true)
        #expect(EffortPredictor.suggestedLevel(from: bailed) == .allOut)
    }

    @Test func twoNetCapHitsSuggestAllOut() {
        #expect(EffortPredictor.suggestedLevel(from: summary(capped: 2)) == .allOut)
    }

    @Test func repeatedBackOffsSuggestHard() {
        #expect(EffortPredictor.suggestedLevel(from: summary(backOffs: 2)) == .hard)
    }

    @Test func oneNetCapHitSuggestsHard() {
        #expect(EffortPredictor.suggestedLevel(from: summary(capped: 1)) == .hard)
    }

    @Test func defiedWalksAreExcusedFromCapHits() {
        // The user chose to run through the walk — that reads from the other signals.
        let defied = summary(capped: 1, defied: 1)
        #expect(EffortPredictor.suggestedLevel(from: defied) == .moderate)
    }

    @Test func mostlyAboveZoneSuggestsHard() {
        let hot = summary(runTime: 600, inZone: 350, aboveZone: 250)
        #expect(EffortPredictor.suggestedLevel(from: hot) == .hard)
    }

    @Test func fastRecoveriesEverywhereWithBigDropSuggestEasy() {
        let easy = summary(walksCompleted: 5, fastRecoveries: 5, meanDrop: 30)
        #expect(EffortPredictor.suggestedLevel(from: easy) == .easy)
    }

    @Test func fastRecoveriesWithoutTheDropStayModerate() {
        let mixed = summary(walksCompleted: 5, fastRecoveries: 5, meanDrop: 18)
        #expect(EffortPredictor.suggestedLevel(from: mixed) == .moderate)
    }

    @Test func unremarkableSessionSuggestsModerate() {
        #expect(EffortPredictor.suggestedLevel(from: summary()) == .moderate)
    }

    @Test func singleBackOffAloneStaysModerate() {
        // One back-off is the converged path's normal calibration, not a hard session.
        #expect(EffortPredictor.suggestedLevel(from: summary(backOffs: 1)) == .moderate)
    }
}
