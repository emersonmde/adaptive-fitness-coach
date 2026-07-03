import AppIntents
import Combine
import Foundation

/// The capture entry point (spec §7): Action Button, Siri, Shortcuts, and a Home-Screen
/// shortcut all open the app straight into the camera — the "widget/icon → camera" golden
/// path without a widget target (the WidgetKit extension is a follow-up build).
struct CaptureMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription("Open the camera to scan a receipt, barcode, or nutrition label.")

    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MealCaptureRequest.shared.requestCapture()
        return .result()
    }
}

/// Hand-off from the intent (which runs before or after scene setup, depending on app state)
/// to WeekView: a flag for cold starts plus a change notification for the warm ones.
@MainActor
final class MealCaptureRequest: ObservableObject {
    static let shared = MealCaptureRequest()
    @Published private(set) var pending = false

    func requestCapture() { pending = true }

    /// Consumes the request (WeekView calls this when it presents the camera).
    func consume() -> Bool {
        defer { pending = false }
        return pending
    }
}

/// System exposure (Shortcuts, Action Button, Siri) — the phone counterpart of the watch's
/// `AdaptiveFitnessShortcuts`.
struct AdaptiveFitnessPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Scan my food in \(.applicationName)",
            ],
            shortTitle: "Log a Meal",
            systemImageName: "camera.viewfinder"
        )
    }
}
