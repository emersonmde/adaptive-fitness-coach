import Foundation
import WatchConnectivity
import AdaptiveCore

/// Receives the routine set pushed from the phone and writes it into the local store.
///
/// One-directional in P0 (phone → watch). Uses `applicationContext`, so the watch always has
/// the latest routines even if it was asleep or the phone is now absent — which is what makes
/// the watch fully usable on its own (N4).
@MainActor
final class WatchConnectivityManager: NSObject {
    private let store: RoutineStore

    init(store: RoutineStore) {
        self.store = store
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Apply a received context if it carries routines. Tolerates malformed payloads by
    /// keeping the last-known set (N6).
    private func apply(context: [String: Any]) {
        guard let routines = try? WCMessageCodec.decodeRoutines(from: context) else { return }
        store.replaceFromSync(routines)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Pick up whatever context already arrived before activation completed.
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        Task { @MainActor in self.apply(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(context: applicationContext) }
    }
}
