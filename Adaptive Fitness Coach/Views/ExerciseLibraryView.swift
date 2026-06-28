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
        return Button {
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
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .opacity(isAdded ? 0.5 : 1)
        .accessibilityIdentifier("exercise_\(exercise.id)")
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

    /// A one-line default prescription, e.g. "3 × 10 · 15 lb", "3 × 12 · bodyweight", "3 × 0:30".
    private func prescription(_ exercise: Exercise) -> String {
        switch exercise.kind {
        case let .reps(reps, weight):
            let load = weight?.displayString() ?? "bodyweight"
            return "\(exercise.defaultSets) × \(reps) · \(load)"
        case let .hold(seconds):
            return "\(exercise.defaultSets) × \(seconds.holdLabel) hold"
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
