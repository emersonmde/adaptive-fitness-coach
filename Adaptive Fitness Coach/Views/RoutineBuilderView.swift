import SwiftUI
import AdaptiveCore

/// The routine builder — a routine is a stack of typed cards (run · exercise · rest), reorderable,
/// each editable inline, with a Rounds control that repeats the whole stack (the routine-level
/// "sets"; a rest card at the end then falls between rounds). The watch walks the cards and starts
/// the right Apple workout per card type automatically.
///
/// Persistence-agnostic: it collects the cards + rounds and hands them to `onCommit`, so it serves
/// both creating a routine and editing one. Days/scheduling live in the routine's detail screen.
struct RoutineBuilderView: View {
    var initialCards: [WorkoutCard] = []
    var initialRounds: Int = 1
    /// Receives the assembled routine on Save. The caller persists (add vs update) and dismisses.
    let onCommit: ([WorkoutCard], Int) -> Void

    @State private var cards: [WorkoutCard] = []
    @State private var rounds = 1
    @State private var showingLibrary = false
    @State private var loaded = false

    private var addedIDs: Set<String> { Set(cards.compactMap(\.exercise).map(\.exerciseId)) }

    /// Rounds only matters once there's something to repeat beyond a single run.
    private var showsRounds: Bool {
        cards.count > 1 || cards.contains { $0.exercise != nil }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if cards.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Build Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if cards.count > 1 {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { onCommit(cards, rounds) }
                    .disabled(cards.isEmpty)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            ExerciseLibraryView(alreadyAdded: addedIDs) { picks in
                cards.append(contentsOf: picks.map { WorkoutCard.exercise(StrengthExerciseItem(from: $0)) })
            }
        }
        .onAppear {
            if !loaded { cards = initialCards; rounds = max(1, initialRounds); loaded = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Build your routine\nfrom cards")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Text("Add a run, an exercise, or a rest — in any order.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            addMenu
        }
        .padding(24)
    }

    private var list: some View {
        List {
            Section {
                ForEach($cards) { $card in
                    CardRow(card: $card)
                        .listRowBackground(Theme.surface1)
                        .listRowSeparatorTint(Theme.hairline)
                }
                .onMove { cards.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { cards.remove(atOffsets: $0) }
            } footer: {
                Text("Drag to reorder · swipe to remove. Weights are a starting point — adjust them on your watch any time.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if showsRounds {
                Section {
                    RoundsRow(rounds: $rounds)
                        .listRowBackground(Theme.surface1)
                } footer: {
                    Text("Repeats the whole routine. A rest card at the end becomes rest between rounds.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Section {
                addMenu.listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// The one add affordance that reveals the card vocabulary.
    private var addMenu: some View {
        Menu {
            Button { showingLibrary = true } label: { Label("Exercise", systemImage: "dumbbell.fill") }
            Button { cards.append(.run(RunCard())) } label: { Label("Adaptive Run", systemImage: "figure.run") }
            Button { cards.append(.rest(RestCard())) } label: { Label("Rest", systemImage: "hourglass") }
        } label: {
            Label("Add card", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }
}

// MARK: - Card rows

/// One row in the builder, dispatching to the right editor for the card's type. The colored icon
/// tile carries the card's identity (green run / blue strength / neutral rest).
private struct CardRow: View {
    @Binding var card: WorkoutCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardIconTile(card: card)
            content
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var content: some View {
        switch card {
        case .run:
            RunCardEditor(card: bind(\.run, fallback: RunCard(), wrap: WorkoutCard.run))
        case .exercise:
            ExerciseCardEditor(item: bind(\.exercise, fallback: StrengthExerciseItem(exerciseId: "push_up"), wrap: WorkoutCard.exercise))
        case .rest:
            RestCardEditor(card: bind(\.rest, fallback: RestCard(), wrap: WorkoutCard.rest))
        }
    }

    /// Build a binding to the card's associated payload, writing the wrapped case back.
    /// The getter tolerates a stale evaluation after reorder/delete (SwiftUI can re-read a
    /// ForEach binding whose row now holds a different case) by falling back to the last
    /// value instead of force-unwrapping into a crash.
    private func bind<T>(_ get: @escaping (WorkoutCard) -> T?, fallback: T, wrap: @escaping (T) -> WorkoutCard) -> Binding<T> {
        Binding(
            get: { get(card) ?? fallback },
            set: { card = wrap($0) }
        )
    }
}

private extension WorkoutCard {
    var run: RunCard? { if case let .run(c) = self { return c }; return nil }
    var rest: RestCard? { if case let .rest(c) = self { return c }; return nil }
}

private struct CardIconTile: View {
    let card: WorkoutCard
    var body: some View {
        let tint = RoutineTheme.tint(forCard: card)
        Image(systemName: RoutineTheme.symbol(forCard: card))
            .font(.headline)
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct RunCardEditor: View {
    @Binding var card: RunCard
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adaptive Run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            MiniStepper(label: "Warm-up min", value: $card.warmupMinutes, range: 0...15, step: 1, identifier: "runWarmupStepper")
            MiniStepper(label: "Run min", value: $card.durationMinutes, range: 5...90, step: 5, identifier: "runBlockStepper")
            MiniStepper(label: "Cool-down min", value: $card.cooldownMinutes, range: 0...15, step: 1, identifier: "runCooldownStepper")
            Text("Warm-up and cool-down are walking. The run block alternates run/walk intervals that grow as your recovery improves.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct RestCardEditor: View {
    @Binding var card: RestCard
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rest")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            MiniStepper(
                label: "Seconds",
                value: Binding(get: { Int(card.seconds) }, set: { card.seconds = TimeInterval($0) }),
                range: 5...300, step: 5,
                identifier: "restSecondsStepper"
            )
            Toggle(isOn: $card.adaptive) {
                Text("Adaptive")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("restAdaptiveToggle")
            Text(card.adaptive
                 ? "Ends early once your heart rate recovers — never below ¾ of this time."
                 : "Runs exactly this long.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct ExerciseCardEditor: View {
    @Binding var item: StrengthExerciseItem
    @State private var showingInfo = false

    private var exercise: Exercise? { ExerciseLibrary.exercise(id: item.exerciseId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(exercise?.name ?? item.exerciseId)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if exercise != nil {
                    Button { showingInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About \(exercise?.name ?? "exercise")")
                }
                Spacer(minLength: 0)
            }
            .sheet(isPresented: $showingInfo) {
                if let exercise { ExerciseInfoSheet(exercise: exercise) }
            }

            if item.isHold {
                MiniStepper(
                    label: "Hold (s)",
                    value: Binding(get: { Int(item.holdSeconds ?? 30) }, set: { item.holdSeconds = TimeInterval(max(5, $0)) }),
                    range: 5...180, step: 5
                )
            } else {
                HStack(spacing: 18) {
                    MiniStepper(label: "Reps", value: Binding(get: { item.reps ?? 0 }, set: { item.reps = max(1, $0) }), range: 1...30)
                }
                weightControl
            }
        }
    }

    @ViewBuilder private var weightControl: some View {
        if let weight = item.seedWeight {
            HStack {
                Text("Weight").font(.caption).foregroundStyle(Theme.textTertiary)
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
            Text("Bodyweight").font(.caption).foregroundStyle(Theme.textTertiary)
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
}

/// The routine-level repeat control — frames the whole card stack as "do all of this N times."
private struct RoundsRow: View {
    @Binding var rounds: Int
    var body: some View {
        HStack {
            Label("Repeat", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            MiniStepper(label: "Rounds", value: $rounds, range: 1...20)
        }
        .padding(.vertical, 4)
    }
}

/// A compact label + numeric ± stepper used inside builder cards.
private struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    /// Stable identifier for UI tests (text queries break on copy changes).
    var identifier: String?

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
                    .frame(minWidth: 28)
                button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
            }
        }
        // One adjustable element for VoiceOver ("Warm-up min, 5, swipe up to adjust") instead
        // of two anonymous "plus"/"minus" buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(identifier ?? "stepper_\(label)")
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
