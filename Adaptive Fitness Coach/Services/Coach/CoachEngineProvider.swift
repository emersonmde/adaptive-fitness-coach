import Foundation
import AdaptiveCore

/// Chooses which `CoachEngine` backs the coach UI — the one place backend selection lives, and
/// the extension point for future engines (Claude API, user API keys, a Settings picker).
///
/// `-simulateCoach` (simulator demos and XCUITests, where Apple Intelligence can't be granted)
/// selects the deterministic scripted engine — the `-simulateWorkout` pattern applied to chat.
enum CoachEngineProvider {
    static func makeEngine() -> any CoachEngine {
        if ProcessInfo.processInfo.arguments.contains("-simulateCoach") {
            return ScriptedCoachEngine.demoIntake(deltaDelay: .milliseconds(20))
        }
        return FoundationModelsCoachEngine()
    }
}
