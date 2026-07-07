import AppIntents
import Combine
import Foundation

/// Lets the Apple Watch Ultra Action Button launch straight into the app's session screen.
///
/// P0 scope: the intent opens the app at the launch screen (A1), where Start begins the run.
/// Binding the Action Button to this intent is done by the user in Settings; full auto-start
/// on trigger is a device-hardening follow-up.
struct StartRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Adaptive Run"
    static let description = IntentDescription("Open Adaptive Fitness Coach to start your run.")

    /// Bring the app to the foreground when triggered (e.g. via the Action Button).
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Starts a *specific* routine's adaptive session (build 9) — the intent behind the watch
/// Smart Stack complication/widget and "Start my Morning Run". Opens the app and routes the
/// session container straight to that routine, bypassing the crown picker, so our adaptive
/// engine runs in-session (N2/N3) rather than handing off to Apple's Workout app.
struct StartRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    // App Intent descriptions must not contain "apple" (ITMS-90626).
    static let description = IntentDescription("Start one of your scheduled routines.")
    static let openAppWhenRun = true

    @Parameter(title: "Routine")
    var routineId: String

    init() {}
    init(routineId: String) { self.routineId = routineId }

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkoutLaunchRequest.shared.request(routineId: routineId)
        return .result()
    }
}

/// Dictate a meal from the wrist (the quick-log complication / Shortcuts): opens the app
/// straight into the quick-log sheet — text is parked for the iPhone's review queue, no
/// lookup on the watch (always-pending).
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription("Dictate a meal — it's saved for review on your phone.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkoutLaunchRequest.shared.requestQuickLog()
        return .result()
    }
}

/// Hand-off from `StartRoutineIntent` (which may fire before or after the scene exists) to
/// `SessionContainerView`: a pending routine id the container consumes to auto-select.
/// Also carries the quick-log complication's "open the meal sheet" request (same
/// fire-before-or-after-scene problem, same consume discipline).
@MainActor
final class WorkoutLaunchRequest: ObservableObject {
    static let shared = WorkoutLaunchRequest()
    @Published private(set) var pendingRoutineId: String?
    @Published private(set) var pendingQuickLog = false

    func request(routineId: String) { pendingRoutineId = routineId }

    func consume() -> String? {
        defer { pendingRoutineId = nil }
        return pendingRoutineId
    }

    func requestQuickLog() { pendingQuickLog = true }

    /// True exactly once per request — consumed even when the container drops it (a session
    /// in progress), so it can't pop a stale sheet after the workout ends.
    func consumeQuickLog() -> Bool {
        defer { pendingQuickLog = false }
        return pendingQuickLog
    }
}

/// Exposes the intents to the system (Shortcuts, Action Button, Siri) without extra setup.
struct AdaptiveFitnessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRunIntent(),
            phrases: ["Start my run in \(.applicationName)"],
            shortTitle: "Start Run",
            systemImageName: "figure.run"
        )
    }
}
