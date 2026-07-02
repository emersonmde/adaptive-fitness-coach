import SwiftUI
import AdaptiveCore

/// P3 — the exercise library: browse the curated catalog grouped by muscle, multi-select, and
/// add the picks to the routine being built. Each row teaches the movement (form diagram, "good
/// for" line, default prescription) before it's ever performed. Read-only catalog; selection is
/// returned to the builder, which seeds editable cards from it.
struct ExerciseLibraryView: View {
    /// Exercise ids the builder already holds, shown as "Added" and not re-selectable.
    let alreadyAdded: Set<String>
    let onAdd: ([Exercise]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []
    @State private var infoExercise: Exercise?

    /// The catalog grouped by the first muscle tag, in a stable order, for sectioned browsing.
    private var groups: [(muscle: String, exercises: [Exercise])] {
        let byMuscle = Dictionary(grouping: ExerciseLibrary.all) { $0.muscleTags.first ?? "Other" }
        return byMuscle
            .map { (muscle: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.muscle < $1.muscle }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.muscle) { group in
                            FieldSection(title: group.muscle.uppercased()) {
                                VStack(spacing: 0) {
                                    ForEach(group.exercises) { exercise in
                                        row(for: exercise)
                                        if exercise.id != group.exercises.last?.id {
                                            Divider().overlay(Theme.hairline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $infoExercise) { ExerciseInfoSheet(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add (\(selected.count))") { commit() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(for exercise: Exercise) -> some View {
        let isAdded = alreadyAdded.contains(exercise.id)
        let isOn = selected.contains(exercise.id)
        return HStack(spacing: 8) {
            // The selectable area (icon + copy + select indicator) — tap anywhere to toggle.
            Button {
                guard !isAdded else { return }
                if isOn { selected.remove(exercise.id) } else { selected.insert(exercise.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbolName(exercise.formDemo))
                        .font(.title3)
                        .foregroundStyle(Theme.strength)
                        .frame(width: 40, height: 40)
                        .background(Theme.strength.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(exercise.goodFor)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                        Text(prescription(exercise))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isAdded ? "checkmark.circle" : (isOn ? "checkmark.circle.fill" : "plus.circle"))
                        .font(.title3)
                        .foregroundStyle(isAdded ? Theme.textTertiary : (isOn ? Theme.accent : Theme.textSecondary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .opacity(isAdded ? 0.5 : 1)
            .accessibilityIdentifier("exercise_\(exercise.id)")

            // A separate info button — learn the movement without selecting it.
            Button { infoExercise = exercise } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("info_\(exercise.id)")
            .accessibilityLabel("About \(exercise.name)")
        }
        .padding(.vertical, 10)
    }

    private func commit() {
        let picks = ExerciseLibrary.all.filter { selected.contains($0.id) }
        onAdd(picks)
        dismiss()
    }

    private func symbolName(_ demo: FormDemo) -> String {
        if case let .symbol(name) = demo { return name }
        return "dumbbell.fill"
    }

    /// A one-line prescription showing the progression band, e.g. "8–12 reps · 20 lb start".
    private func prescription(_ exercise: Exercise) -> String {
        switch exercise.kind {
        case let .reps(range, weight):
            let load = weight.map { "\($0.displayString()) start" } ?? "bodyweight"
            return "\(range.lowerBound)–\(range.upperBound) reps · \(load)"
        case let .hold(seconds):
            return "\(seconds.holdLabel) hold"
        }
    }
}

extension TimeInterval {
    /// Compact `m:ss` label for a hold duration (e.g. `0:30`).
    var holdLabel: String {
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
