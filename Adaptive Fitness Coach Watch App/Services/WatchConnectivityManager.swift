import Foundation
import Observation
import WatchConnectivity
import WidgetKit
import AdaptiveCore

/// Receives the routine set pushed from the phone, and sends recorded progressions back.
///
/// Routines come down one-directionally via `applicationContext`, so the watch always has the
/// latest set even if it was asleep or the phone is now absent (N4). Progressions go *up* via
/// `transferUserInfo`: a separate, FIFO-queued, guaranteed-delivery channel so a weight/rep bump
/// survives the phone being unreachable (every finished session is one queued transfer) — unlike
/// `applicationContext`, which is latest-wins and would drop earlier sessions' changes.
@MainActor
@Observable
final class WatchConnectivityManager: NSObject {
    @ObservationIgnored private let store: RoutineStore

    /// True once ANY application context has come down from the phone (live delivery, or one
    /// the OS already held when activation completed). Lets the UI tell "not synced yet"
    /// apart from "the phone genuinely has no routines" — an empty store plus a false here
    /// means *waiting*, not *nothing exists* (N6: never assert a signal we don't have).
    private(set) var hasReceivedInitialContext = false

    /// The complication timeline kind (`AdaptiveFitnessWatchWidgets`). Anything that changes
    /// the routine set — a sync from the phone or a locally-applied progression — must reload
    /// it, or the "next workout" on the watch face keeps showing yesterday's answer.
    private static let complicationKind = "NextWorkoutComplication"

    /// Batches queued before WCSession activation completed. `transferUserInfo` on an
    /// unactivated session is silently dropped by the OS — and progressions ride the
    /// "guaranteed delivery" channel precisely because losing one loses a workout's learned
    /// seeds — so pre-activation sends buffer here and flush on `activationDidCompleteWith`.
    private var pendingTransfers: [[String: Any]] = []
    private var isActivated = false

    init(store: RoutineStore) {
        self.store = store
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Queue a progression batch for the phone. Guaranteed delivery (queued until reachable) —
    /// but only once the session is activated; earlier sends are buffered, not lost.
    func sendProgression(_ batch: ProgressionBatch) {
        guard WCSession.isSupported(),
              let message = try? WCMessageCodec.encode(progression: batch) else { return }
        if isActivated, WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(message)
        } else {
            pendingTransfers.append(message)
        }
    }

    /// Activation completed: hand the OS everything that queued up while it wasn't ready.
    private func flushPendingTransfers() {
        isActivated = true
        let queued = pendingTransfers
        pendingTransfers = []
        for message in queued {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Record progressions from a finished session: apply them to the local store so the next watch
    /// workout already reflects the new seed, and queue them to the phone (which re-broadcasts the
    /// corrected routine back). `broadcast: false` locally — the watch never broadcasts (N4), and the
    /// phone is the sole re-broadcaster, so the round trip converges without ping-pong.
    func recordProgressions(routineId: UUID, _ updates: [ProgressionUpdate]) {
        store.applyProgressions(updates, toRoutineId: routineId, broadcast: false)
        sendProgression(ProgressionBatch(routineId: routineId, updates: updates))
        WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
    }

    /// Record a finished run session's new interval seeds. Same contract as
    /// `recordProgressions`: apply locally without broadcasting, queue to the phone.
    func recordRunProgression(routineId: UUID, _ updates: [RunProgressionUpdate]) {
        let batch = ProgressionBatch(routineId: routineId, runUpdates: updates)
        store.applyProgressions(batch, broadcast: false)
        sendProgression(batch)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
    }

    /// Apply a received context if it carries routines. Tolerates malformed payloads by
    /// keeping the last-known set (N6). Internal (not private) so the sync-honesty flag is
    /// unit-testable without a live `WCSession`.
    func apply(context: [String: Any]) {
        // Any context at all — even one that fails to decode — proves the phone has spoken,
        // so the UI can stop saying "syncing" either way.
        hasReceivedInitialContext = true
        guard let routines = try? WCMessageCodec.decodeRoutines(from: context) else { return }
        store.replaceFromSync(routines)
        // The routine set just changed under the complication — refresh its timeline so the
        // watch face's "next workout" reflects the new schedule.
        WidgetCenter.shared.reloadTimelines(ofKind: Self.complicationKind)
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Release any progression transfers that were queued before activation completed.
        if activationState == .activated {
            Task { @MainActor in self.flushPendingTransfers() }
        }
        // Pick up whatever context already arrived before activation completed.
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        Task { @MainActor in self.apply(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(context: applicationContext) }
    }
}
