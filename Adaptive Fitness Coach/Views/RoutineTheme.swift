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

    // MARK: - Per-card identity (the builder's card stack)

    /// Semantic tint for a card by type: green run / blue strength / neutral rest. Rest is
    /// deliberately uncolored — it's recovery, not work — so the work cards pop in the stack.
    static func tint(forCard card: WorkoutCard) -> Color {
        switch card {
        case .run: Theme.run
        case .exercise: Theme.strength
        case .rest: Theme.textSecondary
        }
    }

    static func symbol(forCard card: WorkoutCard) -> String {
        switch card {
        case .run: return "figure.run"
        case let .exercise(item):
            if case let .symbol(name) = ExerciseLibrary.exercise(id: item.exerciseId)?.formDemo { return name }
            return "dumbbell.fill"
        case .rest: return "hourglass"
        }
    }
}
