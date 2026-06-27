import AppIntents

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

/// Exposes the intent to the system (Shortcuts, Action Button) without extra setup.
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
