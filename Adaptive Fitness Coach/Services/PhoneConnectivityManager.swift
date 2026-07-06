import Foundation
import OSLog
import WatchConnectivity
import AdaptiveCore

/// Sends the user's routines from the phone to the watch.
///
/// P0 connectivity is one-directional: the phone owns the routine set and pushes the latest
/// state to the watch with `updateApplicationContext`, which delivers only the most recent
/// payload, survives the counterpart being unreachable, and is queued by the OS until the
/// watch is available. That matches "watch-first, phone-optional" (N4) — the watch always
/// has the last-known routines without the phone needing to be present at workout time.
@MainActor
final class PhoneConnectivityManager: NSObject {
    static let shared = PhoneConnectivityManager()

    private var session: WCSession { .default }

    /// The routine store, set at app launch. Inbound progressions (watch → phone) are applied here.
    weak var store: RoutineStore?
    /// The progression journal + structural-proposal store (P6), set at app launch alongside
    /// `store`. Inbound batches land through `ProgressionIntake` so every applied change is
    /// journaled and structural proposals wait for the user's confirm.
    weak var journal: ProgressionJournal?
    weak var proposals: ProgressionProposalStore?
    /// The watch quick-log handler (P6), set at app launch. `transferUserInfo` deliveries
    /// (the always-pending path) and legacy live `sendMessage` round trips (build-≤17
    /// watches) both land here; the manager stays transport.
    weak var quickLog: (any QuickLogHandling)?

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    /// Push the full routine set to the watch. Safe to call on every routine change.
    func sync(routines: [Routine]) {
        guard WCSession.isSupported() else { return }
        guard session.activationState == .activated else { return }
        do {
            let context = try WCMessageCodec.encode(routines: routines)
            try session.updateApplicationContext(context)
        } catch {
            // Non-fatal: transient unreachability does not throw (the OS delivers the latest
            // context once the watch is reachable); this catch only fires on an encode/state
            // error, where the watch simply keeps its last-known routines.
            Logger(subsystem: "com.memerson.Adaptive-Fitness-Coach", category: "connectivity")
                .error("PhoneConnectivity sync failed: \(error)")
        }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // The launch-time sync races activation (`sync` bails while not yet .activated), so a
        // first install would leave the watch empty until the user's next edit. Re-push the
        // current set the moment activation lands.
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let routines = self.store?.routines, !routines.isEmpty {
                self.sync(routines: routines)
            }
        }
    }

    /// The watch app was (re)installed, or the paired watch changed. A reinstall drops the
    /// OS-held application context, and the only other pushes are routine edits and this
    /// process's one activation — so without this, a fresh watch install stares at
    /// "Syncing from iPhone…" until it times out into a false empty state while the phone
    /// holds routines (hit on real hardware installing build 18).
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        Task { @MainActor in
            if let routines = self.store?.routines, !routines.isEmpty {
                self.sync(routines: routines)
            }
        }
    }

    // Required on iOS so the session can re-activate after switching watches.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for the newly-paired watch.
        WCSession.default.activate()
    }

    /// A progression recorded on the watch (a weight/rep bump). Apply it to the matching routine and
    /// re-broadcast so the corrected routine flows back to the watch. The apply is idempotent
    /// latest-value and short-circuits once converged, so this round trip reaches a fixed point and
    /// cannot ping-pong. A malformed/unrelated transfer is ignored (N6).
    /// LEGACY live quick-log round trip (build-≤17 watches; new watches are always-pending
    /// and never send this): the watch is waiting on the reply handler, so a failure to
    /// produce a draft replies an EMPTY dictionary — the old watch treats that as "couldn't
    /// look it up" and offers its offline fallback (never a fabricated number).
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            guard let inbound = try? WCMessageCodec.decodeQuickLog(from: message),
                  let handler = self.quickLog,
                  let reply = await handler.handleLive(inbound),
                  let encoded = try? WCMessageCodec.encode(quickLog: reply) else {
                replyHandler([:])
                return
            }
            replyHandler(encoded)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // The userInfo channel carries two message families — demux by payload key.
        if let quickLogMessage = try? WCMessageCodec.decodeQuickLog(from: userInfo) {
            Task { @MainActor in
                self.quickLog?.handleOffline(quickLogMessage)
            }
            return
        }
        Task { @MainActor in
            guard let batch = try? WCMessageCodec.decodeProgression(from: userInfo),
                  let store = self.store else { return }
            if let journal = self.journal, let proposals = self.proposals {
                // P6 path: apply micro + journal it, stash structural proposals for the card.
                ProgressionIntake.receive(batch, store: store, journal: journal, proposals: proposals)
            } else {
                store.applyProgressions(batch, broadcast: true)
            }
        }
    }
}
