import SwiftUI
import AdaptiveCore

/// A wrapper so a parsed-but-not-yet-applied import can drive a `.sheet(item:)`.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let routines: [Routine]
}

/// Confirms a routine import (typically the JSON Claude returned, parsed by `RoutineExchange`)
/// before it touches the store. Shows each incoming routine, whether it updates an existing one
/// (matched by name) or is new, and what it contains — so a paste never silently overwrites work.
struct ImportRoutinesSheet: View {
    let candidate: ImportCandidate
    let existingNames: Set<String>
    /// Apply the import; returns (updated, added) for the confirmation.
    let onApply: ([Routine]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Review what Claude sent before it's applied. Matching names update your existing routines; the rest are added.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(candidate.routines) { routine in
                            FieldSection(title: existingNames.contains(routine.name) ? "UPDATES \(routine.name.uppercased())" : "NEW · \(routine.name.uppercased())") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(routine.cards.enumerated()), id: \.offset) { _, card in
                                        Text("• \(cardSummary(card))")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    if routine.rounds > 1 {
                                        Text("Repeats \(routine.rounds)×")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Import \(candidate.routines.count) Routine\(candidate.routines.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(candidate.routines); dismiss() }
                }
            }
        }
    }

    private func cardSummary(_ card: WorkoutCard) -> String {
        switch card {
        case let .run(c):
            return "Run \(c.durationMinutes) min (+\(c.warmupMinutes)+\(c.cooldownMinutes) walk)"
        case let .exercise(item):
            let name = ExerciseLibrary.exercise(id: item.exerciseId)?.name ?? item.exerciseId
            if let hold = item.holdSeconds { return "\(name) — \(Int(hold))s hold" }
            let load = item.seedWeight.map { " · \($0.displayString())" } ?? " · bodyweight"
            return "\(name) — \(item.reps ?? 0) reps\(load)"
        case let .rest(c):
            return "Rest \(Int(c.seconds))s"
        }
    }
}
