import Foundation
import HealthKit

/// Crash recovery for the live workout (build 10). If the app dies mid-workout (crash, OS jetsam,
/// forced quit), the `HKWorkoutSession` survives in the OS — sensors hot, and any subsequent
/// `start()` can fail against the orphan. The engine's in-memory state (interval machine,
/// adaptation integrators) died with the process, so *resuming* the guidance isn't honest — but
/// the collected samples are real and belong to the user (N2: the OS is the system of record).
///
/// Scope is therefore **recover-and-finalize**: reattach to the orphaned session, end it, and
/// finish its builder so the workout lands in Apple Health, then leave the app idle for a clean
/// next start. Called from app launch and from `WKApplicationDelegate.handleActiveWorkoutRecovery`
/// (the OS's explicit "you have a session to recover" relaunch hook) — both funnel here, and a
/// one-shot guard keeps the two entry points from double-finalizing the same session.
@MainActor
enum WorkoutRecoveryService {
    /// Both entry points (app-launch task and the delegate recovery hook) can fire in the same
    /// process; only the first attempt should touch the session.
    private static var hasAttempted = false

    /// Recover any orphaned workout session and finalize it into Health. Safe to call when
    /// nothing needs recovering (the OS reports no session and this is a no-op). Never called
    /// on the simulated/scripted paths — the caller guards on the `-simulate*` launch args.
    static func recoverAndFinalizeAbandonedSession() async {
        guard !hasAttempted else { return }
        hasAttempted = true
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let store = HealthKitAuthorization.healthStore
        let session: HKWorkoutSession? = await withCheckedContinuation { continuation in
            // Completion fires with (nil, error) when there's nothing to recover — treat any
            // error the same as "no session": there is nothing we can act on (N6).
            store.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        guard let session else { return }

        // End the session (if the OS hasn't already) and finish its builder so the samples the
        // live builder collected before the crash persist as a real Apple workout (N2). The
        // recovered builder needs no data source — we're closing the books, not collecting.
        let builder = session.associatedWorkoutBuilder()
        if session.state != .ended, session.state != .notStarted {
            session.end()
        }
        do {
            try await HealthKitWorkoutBackend.endCollectionSettling(builder, at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            // Best-effort: the samples were live-collected and may already be in Health; a
            // failed finalize must never block the app from reaching a clean idle state.
        }
    }
}
