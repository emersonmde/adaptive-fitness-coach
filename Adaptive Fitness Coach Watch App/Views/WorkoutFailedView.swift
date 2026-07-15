import SwiftUI

/// The one failure screen for every workout flow (run, strength, sequence block) — replacing
/// three divergent ad-hoc views (W1/W3/W4, T2). Two honest shapes:
///
/// - **Failed to start**: nothing ever ran, nothing was saved, retrying is safe — so the
///   primary action is a full-width Try Again ABOVE the fold. Copy mentions Health
///   permissions ONLY when the classified cause is `.permissionsDenied` (W5), and names the
///   destination the user can actually go fix it at.
/// - **Failed mid-session**: the workout died after starting. The builder was collecting
///   live, so partial data may already be in Health — this screen must never claim "nothing
///   was saved" (B1). Shows the elapsed at death; no Try Again (the session is gone), and
///   no celebration styling.
///
/// Actions are a slot (`@ViewBuilder`) so callers keep their own exits — the standalone
/// containers use Try Again/Back or Done, the sequence keeps "Skip this part"/"End workout".
struct WorkoutFailedView<Actions: View>: View {
    enum Failure: Equatable {
        case start(StartFailureCause)
        case midSession(elapsed: TimeInterval)
    }

    let failure: Failure
    @ViewBuilder let actions: () -> Actions

    private var title: String {
        switch failure {
        case .start: "Couldn't start"
        case .midSession: "Ended unexpectedly"
        }
    }

    private var message: String {
        switch failure {
        case .start(.permissionsDenied):
            "Health access is off, so the workout can't start. Allow it in "
                + "iPhone → Health → Sharing. Nothing was saved."
        case .start(.unknown):
            "Something went wrong starting the workout. Nothing was saved."
        case let .midSession(elapsed) where elapsed > 0:
            "The workout stopped on its own after \(elapsed.clockString). "
                + "What was recorded is in Health."
        case .midSession:
            "The workout stopped on its own. What was recorded is in Health."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(WatchTheme.heat)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                // The actions sit directly under the copy — the primary exit (Try Again /
                // Done) must be reachable without scrolling on a wrist peek.
                actions()
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
        }
    }
}

/// The standard start-failure actions: full-width Try Again primary, quiet Back secondary.
/// Retrying is safe — a failed start left nothing running (the backends end any half-started
/// session before surfacing the error).
struct RetryFailedActions: View {
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            Button("Back", role: .cancel, action: onBack)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }
}
