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
    ///
    /// PERSISTED to disk on every mutation: the buffer holds the only copy of a quick-log or
    /// progression until WCSession accepts it, and the watch UI has already confirmed the
    /// save ("Saved for iPhone") — an app termination before activation completes must not
    /// silently discard it (N6). Once handed to `transferUserInfo` the OS owns delivery
    /// (its queue survives relaunches), so rows are dropped from here only at that point.
    private var pendingTransfers: [[String: Any]] = [] {
        didSet { Self.persistPendingTransfers(pendingTransfers, to: transfersURL) }
    }
    private var isActivated = false
    @ObservationIgnored private let transfersURL: URL

    /// Internal (not private) so the persistence round trip is unit-testable without a
    /// live `WCSession` (same pattern as `hasReceivedInitialContext`).
    var pendingTransferCount: Int { pendingTransfers.count }

    private static let defaultTransfersURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-transfers.plist")
    }()

    private static func persistPendingTransfers(_ transfers: [[String: Any]], to url: URL) {
        guard !transfers.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // Payloads are codec dictionaries (String keys, Data/Int values) — plist-safe.
        if let data = try? PropertyListSerialization.data(fromPropertyList: transfers, format: .binary, options: 0) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadPendingTransfers(from url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return [] }
        return list as? [[String: Any]] ?? []
    }

    init(store: RoutineStore, transfersURL: URL = WatchConnectivityManager.defaultTransfersURL) {
        self.store = store
        self.transfersURL = transfersURL
        super.init()
        // Anything buffered when the app last quit still needs the phone.
        pendingTransfers = Self.loadPendingTransfers(from: transfersURL)
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

    // MARK: - Quick-log (P6): always-pending

    /// Park the dictated text in the guaranteed-delivery queue. It lands in the phone's
    /// pending-REVIEW flow — surfaced with a card, committed only after the user sees it
    /// there (same buffering discipline as `sendProgression`). This is the quick-log's ONLY
    /// channel: the live `sendMessage` draft/confirm round trips were removed because a
    /// locked, backgrounded phone can't run the lookup ladder inside WCSession's reply
    /// deadline — the wrist would wait minutes and then fail anyway.
    func queueQuickLogOffline(_ request: QuickLogRequest) {
        guard WCSession.isSupported(),
              let message = try? WCMessageCodec.encode(quickLog: .request(request)) else { return }
        if isActivated, WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(message)
        } else {
            pendingTransfers.append(message)
        }
    }

    /// Activation completed: hand the OS everything that queued up while it wasn't ready.
    /// Hand-over precedes the clear so a death mid-flush re-sends next launch instead of
    /// losing rows — at-least-once by design (progression applies are idempotent; a rare
    /// duplicate review card beats a lost meal).
    private func flushPendingTransfers() {
        isActivated = true
        for message in pendingTransfers {
            WCSession.default.transferUserInfo(message)
        }
        pendingTransfers = []
    }

    /// Record a finished session's progression batch: apply the **micro lanes only** to the
    /// local store so the next watch workout already reflects the new seed, and queue the
    /// whole batch to the phone (which re-broadcasts the corrected routine back).
    /// `broadcast: false` locally — the watch never broadcasts (N4), and the phone is the sole
    /// re-broadcaster, so the round trip converges without ping-pong. Structural proposals are
    /// deliberately NOT applied here (P6): the phone gates them behind the user's confirm, and
    /// the confirmed seed arrives back via the normal routine sync.
    func record(_ batch: ProgressionBatch) {
        if !batch.updates.isEmpty || !batch.runUpdates.isEmpty {
            store.applyProgressions(
                ProgressionBatch(routineId: batch.routineId,
                                 updates: batch.updates, runUpdates: batch.runUpdates),
                broadcast: false
            )
        }
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
