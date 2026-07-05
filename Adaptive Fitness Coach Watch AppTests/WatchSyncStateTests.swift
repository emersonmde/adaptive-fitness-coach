import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// The first-launch sync-honesty signal (P5): an empty store plus a false
/// `hasReceivedInitialContext` means "waiting on the phone", not "nothing exists" (N6) — the
/// session container shows "Syncing from iPhone…" instead of the create-a-routine empty state
/// until the flag flips (or its 10s fallback gives up). These tests drive `apply(context:)`
/// directly — the same entry point both `WCSessionDelegate` paths funnel through — so the flag
/// is covered without a live `WCSession`.
@MainActor
struct WatchSyncStateTests {

    /// A store on a throwaway file so tests never touch the real routines.json.
    private func makeStore() -> RoutineStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-state-\(UUID().uuidString).json")
        return RoutineStore(fileURL: url)
    }

    @Test func startsUnsynced() {
        let manager = WatchConnectivityManager(store: makeStore())
        #expect(!manager.hasReceivedInitialContext)
    }

    @Test func validContextSetsFlagAndFillsStore() throws {
        let store = makeStore()
        let manager = WatchConnectivityManager(store: store)
        let routines = [Routine(name: "Morning Run", cards: [.run(RunCard())])]

        manager.apply(context: try WCMessageCodec.encode(routines: routines))

        #expect(manager.hasReceivedInitialContext)
        #expect(store.routines.map(\.name) == ["Morning Run"])
    }

    /// Even a malformed payload proves the phone has spoken — the flag flips (the UI stops
    /// claiming "syncing") while the store keeps its last-known set (N6).
    @Test func malformedContextSetsFlagButKeepsStore() {
        let store = makeStore()
        let manager = WatchConnectivityManager(store: store)

        manager.apply(context: ["junk": 1])

        #expect(manager.hasReceivedInitialContext)
        #expect(store.routines.isEmpty)
    }

    /// An empty phone library is still a completed sync: zero routines must land as the
    /// genuine empty state, never as an eternal "syncing" spinner.
    @Test func emptyRoutineSetStillCountsAsSynced() throws {
        let store = makeStore()
        let manager = WatchConnectivityManager(store: store)

        manager.apply(context: try WCMessageCodec.encode(routines: []))

        #expect(manager.hasReceivedInitialContext)
        #expect(store.routines.isEmpty)
    }
}
