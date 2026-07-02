import Foundation
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
            #if DEBUG
            print("PhoneConnectivity sync failed: \(error)")
            #endif
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
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            guard let batch = try? WCMessageCodec.decodeProgression(from: userInfo) else { return }
            self.store?.applyProgressions(batch, broadcast: true)
        }
    }
}
