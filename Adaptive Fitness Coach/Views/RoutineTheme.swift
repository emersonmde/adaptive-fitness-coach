import SwiftUI
import AdaptiveCore

/// Shared color semantics across the phone UI, matching the watch: green = run, blue = strength.
/// Keeping this in one place means the phone and watch read the same at a glance. Uses the
/// design-token semantics (`Theme.run` / `Theme.strength`), not raw system colors.
enum RoutineTheme {
    static func tint(for type: RoutineType) -> Color {
        switch type {
        case .adaptiveRun: Theme.run
        case .strength: Theme.strength
        }
    }

    static func symbol(for type: RoutineType) -> String {
        switch type {
        case .adaptiveRun: "figure.run"
        case .strength: "dumbbell.fill"
        }
    }
}
