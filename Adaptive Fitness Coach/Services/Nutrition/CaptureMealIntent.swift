import AppIntents
import Combine
import Foundation
import AdaptiveCore

/// The capture entry points (spec §7 + build 8): Action Button, Siri, Shortcuts, and widget
/// deep links all funnel through `MealCaptureRequest` into the same pipeline the in-app
/// buttons use.

/// Opens straight into the camera.
struct CaptureMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Meal"
    static let description = IntentDescription("Open the camera to scan a receipt, barcode, or nutrition label.")

    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MealCaptureRequest.shared.request(.scan)
        return .result()
    }
}

/// The Siri path (build 8): "Log a meal" → Siri asks "What did you eat?" → the dictated text
/// flows through the typed pipeline (stated calories and "yesterday" both honored by the
/// deterministic parsers). With iOS 27's App-Intents-based Siri, the parameter may also fill
/// one-shot from a longer utterance.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Meal"
    static let description = IntentDescription(
        "Log food you ate by describing it — the name, where it's from, optionally a calorie count and when ('chicken caesar salad from Wendy's, yesterday')."
    )

    static let openAppWhenRun = true

    @Parameter(
        title: "What did you eat?",
        description: "The food, optionally with a calorie count and a day, e.g. 'salmon caesar salad, 400 calories, yesterday'.",
        requestValueDialog: "What did you eat?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        MealCaptureRequest.shared.request(.typed(text))
        return .result()
    }
}

/// Answers "when is my next workout" with a spoken/snippet dialog — no app foregrounding.
struct NextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Workout"
    static let description = IntentDescription("Tells you when your next scheduled workout is.")

    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Read the same store file the app uses; the intent may run without the app alive.
        let store = RoutineStore(fileURL: nil, onChange: { _ in })
        guard let next = store.nextOccurrence() else {
            return .result(dialog: "Nothing is scheduled. Open Adaptive Fitness Coach to plan your week.")
        }
        let day = next.date.formatted(.dateTime.weekday(.wide))
        let time = next.date.formatted(.dateTime.hour().minute())
        let relative: String
        if Calendar.current.isDateInToday(next.date) {
            relative = "today at \(time)"
        } else if Calendar.current.isDateInTomorrow(next.date) {
            relative = "tomorrow at \(time)"
        } else {
            relative = "\(day) at \(time)"
        }
        return .result(dialog: "\(IntentDialog(stringLiteral: "\(next.routine.name), \(relative)."))")
    }
}

/// Hand-off from intents/deep-links (which may run before or after scene setup) to WeekView:
/// a flag for cold starts plus a change notification for warm ones.
@MainActor
final class MealCaptureRequest: ObservableObject {
    enum Payload: Equatable {
        case scan
        case type            // open the typed-entry sheet
        case typed(String)   // Siri already has the text — go straight to identify
    }

    static let shared = MealCaptureRequest()
    @Published private(set) var pending: Payload?

    func request(_ payload: Payload) { pending = payload }

    /// Routes a widget/URL deep link (afcoach://log/scan | afcoach://log/type).
    func handle(url: URL) {
        guard url.scheme == "afcoach", url.host == "log" else { return }
        switch url.lastPathComponent {
        case "scan": request(.scan)
        case "type": request(.type)
        default: break
        }
    }

    /// Consumes the request (WeekView calls this when it acts on it).
    func consume() -> Payload? {
        defer { pending = nil }
        return pending
    }
}

/// System exposure (Shortcuts, Action Button, Siri) — the phone counterpart of the watch's
/// `AdaptiveFitnessShortcuts`.
struct AdaptiveFitnessPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
            ],
            shortTitle: "Log a Meal",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: CaptureMealIntent(),
            phrases: [
                "Scan a meal in \(.applicationName)",
                "Scan my food in \(.applicationName)",
            ],
            shortTitle: "Scan a Meal",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: NextWorkoutIntent(),
            phrases: [
                "When is my next workout in \(.applicationName)",
                "What's my next workout in \(.applicationName)",
            ],
            shortTitle: "Next Workout",
            systemImageName: "figure.run"
        )
    }
}
