import SwiftUI
import AdaptiveCore

/// Shared color semantics across the phone UI, matching the watch: green = run, blue = strength.
/// Keeping this in one place means the phone and watch read the same at a glance.
enum RoutineTheme {
    static func tint(for type: RoutineType) -> Color {
        switch type {
        case .adaptiveRun: .green
        case .strength: .blue
        }
    }

    static func symbol(for type: RoutineType) -> String {
        switch type {
        case .adaptiveRun: "figure.run"
        case .strength: "dumbbell.fill"
        }
    }
}
