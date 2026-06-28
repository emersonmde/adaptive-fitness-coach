import SwiftUI
import AdaptiveCore

/// P4 — arrange-as-cards: the ordered exercise sequence for a strength routine. Add from the
/// library, reorder, tune each card's sets / reps / seed weight, remove. The seed weights are
/// conservative defaults the user nudges — not a log (N1/N7).
///
/// The view is persistence-agnostic: it collects the card list and hands it to `onCommit`, so it
/// serves both creating a routine (the new-routine flow `add`s) and editing one (the detail
/// screen `update`s). Days and scheduling are handled in the routine's detail screen.
struct RoutineBuilderView: View {
    var initialItems: [StrengthExerciseItem] = []
    /// Receives the assembled sequence on Save. The caller persists (add vs update) and dismisses.
    let onCommit: ([StrengthExerciseItem]) -> Void

    @State private var items: [StrengthExerciseItem] = []
    @State private var showingLibrary = false
    @State private var loaded = false

    private var addedIDs: Set<String> { Set(items.map(\.exerciseId)) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Arrange")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Edit toggles reorder/remove; the steppers stay usable in normal mode. Shown only
            // when there's more than one card to arrange.
            if items.count > 1 {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(items.isEmpty)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            ExerciseLibraryView(alreadyAdded: addedIDs) { picks in
                items.append(contentsOf: picks.map { StrengthExerciseItem(from: $0) })
            }
        }
        .onAppear {
            // Seed from the initial sequence once (editing an existing routine).
            if !loaded { items = initialItems; loaded = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.strength)
            Text("Add exercises to build\nyour sequence")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            addButton
        }
        .padding(24)
    }

    private var list: some View {
        List {
            Section {
                ForEach($items) { $item in
                    ExerciseBuilderRow(item: $item)
                        .listRowBackground(Theme.surface1)
                        .listRowSeparatorTint(Theme.hairline)
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { items.remove(atOffsets: $0) }
            } footer: {
                Text("Drag to reorder · swipe to remove. Weights are a starting point — adjust them on your watch any time.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section {
                addButton
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var addButton: some View {
        Button {
            showingLibrary = true
        } label: {
            Label("Add Exercises", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        onCommit(items)
    }
}

/// One editable card in the builder: the movement, its sets/reps (or hold), and seed weight.
private struct ExerciseBuilderRow: View {
    @Binding var item: StrengthExerciseItem

    private var exercise: Exercise? { ExerciseLibrary.exercise(id: item.exerciseId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.headline)
                    .foregroundStyle(Theme.strength)
                Text(exercise?.name ?? item.exerciseId)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 18) {
                MiniStepper(label: "Sets", value: Binding(
                    get: { item.sets },
                    set: { item.sets = max(1, $0) }
                ), range: 1...8)

                if item.isHold {
                    holdControl
                } else {
                    MiniStepper(label: "Reps", value: Binding(
                        get: { item.reps ?? 0 },
                        set: { item.reps = max(1, $0) }
                    ), range: 1...30)
                }
            }

            if !item.isHold { weightControl }
        }
        .padding(.vertical, 6)
    }

    private var holdControl: some View {
        let seconds = Int(item.holdSeconds ?? 30)
        return MiniStepper(label: "Hold (s)", value: Binding(
            get: { seconds },
            set: { item.holdSeconds = TimeInterval(max(5, $0)) }
        ), range: 5...120, step: 5)
    }

    @ViewBuilder private var weightControl: some View {
        if let weight = item.seedWeight {
            HStack {
                Text("Weight")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                HStack(spacing: 10) {
                    weightButton("minus") { item.seedWeight = weight.adjusted(byPounds: -5) }
                    Text(weight.displayString())
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.strength)
                        .frame(minWidth: 56)
                    weightButton("plus") { item.seedWeight = weight.adjusted(byPounds: 5) }
                }
            }
        } else {
            Text("Bodyweight")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func weightButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var symbolName: String {
        if case let .symbol(name) = exercise?.formDemo { return name }
        return "dumbbell.fill"
    }
}

/// A compact label + numeric ± stepper used for sets / reps / hold inside a builder card.
private struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                Text("\(value)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 24)
                button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 30, height: 30)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
