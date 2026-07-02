import Foundation
import WatchConnectivity
import AdaptiveCore

/// Receives the routine set pushed from the phone, and sends recorded progressions back.
///
/// Routines come down one-directionally via `applicationContext`, so the watch always has the
/// latest set even if it was asleep or the phone is now absent (N4). Progressions go *up* via
/// `transferUserInfo`: a separate, FIFO-queued, guaranteed-delivery channel so a weight/rep bump
/// survives the phone being unreachable (every finished session is one queued transfer) — unlike
/// `applicationContext`, which is latest-wins and would drop earlier sessions' changes.
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

    /// Queue a progression batch for the phone. Guaranteed delivery (queued until reachable).
    func sendProgression(_ batch: ProgressionBatch) {
        guard WCSession.isSupported(),
              let message = try? WCMessageCodec.encode(progression: batch) else { return }
        WCSession.default.transferUserInfo(message)
    }

    /// Record progressions from a finished session: apply them to the local store so the next watch
    /// workout already reflects the new seed, and queue them to the phone (which re-broadcasts the
    /// corrected routine back). `broadcast: false` locally — the watch never broadcasts (N4), and the
    /// phone is the sole re-broadcaster, so the round trip converges without ping-pong.
    func recordProgressions(routineId: UUID, _ updates: [ProgressionUpdate]) {
        store.applyProgressions(updates, toRoutineId: routineId, broadcast: false)
        sendProgression(ProgressionBatch(routineId: routineId, updates: updates))
    }

    /// Record a finished run session's new interval seeds. Same contract as
    /// `recordProgressions`: apply locally without broadcasting, queue to the phone.
    func recordRunProgression(routineId: UUID, _ updates: [RunProgressionUpdate]) {
        let batch = ProgressionBatch(routineId: routineId, runUpdates: updates)
        store.applyProgressions(batch, broadcast: false)
        sendProgression(batch)
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
