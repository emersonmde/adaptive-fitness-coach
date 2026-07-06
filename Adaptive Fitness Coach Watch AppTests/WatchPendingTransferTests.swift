import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// The pre-activation transfer buffer must survive app termination: it holds the ONLY copy
/// of a quick-log (whose UI already said "Saved for iPhone") or a progression batch until
/// WCSession accepts it, so it persists to disk on every mutation (N6 — never confirm a
/// save that can silently vanish). These tests drive the buffer through the public queue
/// methods pre-activation — no live `WCSession` round trip is involved.
@MainActor
struct WatchPendingTransferTests {

    private func makeStore() -> RoutineStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-store-\(UUID().uuidString).json")
        return RoutineStore(fileURL: url)
    }

    private func tempTransfersURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-transfers-\(UUID().uuidString).plist")
    }

    @Test func quickLogBufferedPreActivationSurvivesRelaunch() {
        let url = tempTransfersURL()
        let store = makeStore()

        let first = WatchConnectivityManager(store: store, transfersURL: url)
        first.queueQuickLogOffline(QuickLogRequest(text: "two tacos"))
        #expect(first.pendingTransferCount == 1)

        // A fresh manager over the same file = the app relaunching after termination.
        let second = WatchConnectivityManager(store: store, transfersURL: url)
        #expect(second.pendingTransferCount == 1)
    }

    @Test func progressionBatchesAccumulateAndPersist() {
        let url = tempTransfersURL()
        let store = makeStore()

        let first = WatchConnectivityManager(store: store, transfersURL: url)
        first.queueQuickLogOffline(QuickLogRequest(text: "greek yogurt"))
        first.sendProgression(ProgressionBatch(routineId: UUID(), updates: [], runUpdates: []))
        #expect(first.pendingTransferCount == 2)

        let second = WatchConnectivityManager(store: store, transfersURL: url)
        #expect(second.pendingTransferCount == 2)
    }

    @Test func freshManagerStartsEmpty() {
        let manager = WatchConnectivityManager(store: makeStore(), transfersURL: tempTransfersURL())
        #expect(manager.pendingTransferCount == 0)
    }
}
