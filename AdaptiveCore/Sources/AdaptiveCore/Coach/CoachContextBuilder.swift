import Foundation

/// Builds the read-only `CoachContext` an engine gets at session start. Reuses the exchange
/// export (the same schema the model proposes in) and renders earned progression as prose the
/// coach can reason about but not write back (the output schema omits seeds; the store's graft
/// restores them regardless — belt and suspenders).
public enum CoachContextBuilder {
    public static func context(
        for intent: CoachIntent,
        routines: [Routine],
        library: [Exercise] = ExerciseLibrary.all
    ) -> CoachContext {
        switch intent {
        case .buildNewPlan:
            // A fresh plan starts from intake, not from what exists. Existing names still
            // matter (a colliding name would merge on import), so pass them via the summary.
            let names = routines.map(\.name)
            let note = names.isEmpty ? nil :
                "The user already has routines named: \(names.joined(separator: ", ")). " +
                "Give new routines different names unless the user asks to replace one."
            return CoachContext(progressionSummary: note)

        case let .reviseRoutine(id):
            guard let routine = routines.first(where: { $0.id == id }) else { return .empty }
            return CoachContext(
                routinesJSON: RoutineExchange.exportJSON([routine]),
                progressionSummary: progressionSummary([routine], library: library),
                focusRoutineName: routine.name
            )

        case .reviseAll:
            guard !routines.isEmpty else { return .empty }
            return CoachContext(
                routinesJSON: RoutineExchange.exportJSON(routines),
                progressionSummary: progressionSummary(routines, library: library)
            )
        }
    }

    /// Earned state the exchange schema deliberately omits, as human-readable lines: current
    /// run/walk seeds and calibration, and per-exercise current prescriptions. This is how the
    /// coach judges experience ("12 reps at 25 lb on goblet squats — ready for more") without
    /// ever being able to write seeds.
    public static func progressionSummary(
        _ routines: [Routine],
        library: [Exercise] = ExerciseLibrary.all
    ) -> String? {
        var lines: [String] = []
        for routine in routines {
            var details: [String] = []
            for card in routine.cards {
                switch card {
                case let .run(run):
                    let calibration = run.seedsCalibrated
                        ? "earned from real sessions"
                        : "not yet calibrated (defaults)"
                    details.append(
                        "run intervals: \(run.runSeconds)s run / \(run.walkSeconds)s walk (\(calibration))"
                    )
                case let .exercise(item):
                    let name = library.first { $0.id == item.exerciseId }?.name ?? item.exerciseId
                    if let hold = item.holdSeconds {
                        details.append("\(name): \(Int(hold))s hold")
                    } else {
                        let load = item.seedWeight.map { " @ \($0.displayString())" } ?? " (bodyweight)"
                        details.append("\(name): \(item.reps ?? 0) reps\(load)")
                    }
                case .rest:
                    continue
                }
            }
            if !details.isEmpty {
                lines.append("\(routine.name): " + details.joined(separator: "; "))
            }
        }
        guard !lines.isEmpty else { return nil }
        return "Current working levels (earned progression — treat as demonstrated fitness):\n"
            + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}
