import SwiftUI
import AdaptiveCore

/// The strength flow: B0 launch → B1/B2 card sequence → complete. Mirrors the run container but
/// drives a `StrengthSessionManager` (user-advanced, no real-time adaptation in P1).
struct StrengthSessionContainerView: View {
    let store: RoutineStore
    var recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?
    @State private var manager: StrengthSessionManager
    private let simulate: Bool

    init(store: RoutineStore, simulate: Bool,
         recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)? = nil) {
        self.store = store
        self.simulate = simulate
        self.recordProgressions = recordProgressions
        _manager = State(initialValue: simulate
            ? StrengthSessionManager(backend: SimulatedStrengthBackend())
            : StrengthSessionManager())
    }

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle:
                StrengthLaunchView(routine: nextRoutine, exerciseCount: exerciseCount, onStart: start)
            case .active:
                StrengthSessionPager(manager: manager)
            case .complete:
                if let summary = manager.summary {
                    StrengthCompleteView(summary: summary) { manager.reset() }
                } else {
                    ProgressView()
                }
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The workout couldn't start. Nothing was saved. Check Health permissions and try again.")
                } actions: {
                    Button("Back") { manager.reset() }
                }
            }
        }
        .task {
            manager.onProgressions = recordProgressions
            if simulate, manager.sessionState == .idle { start() }
        }
    }

    /// The cards the watch will run: the next strength routine's cards (round-expanded), or a
    /// compact demo under `-simulateStrength`. Runs are filtered out by the manager.
    private var sessionCards: [WorkoutCard] {
        if simulate { return Self.demoCards }
        return nextRoutine?.expandedCards ?? []
    }

    private var exerciseCount: Int { sessionCards.reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) } }

    /// The next strength routine, by weekday/time, falling back to any strength routine.
    private var nextRoutine: Routine? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = DayOfWeek(rawValue: calendar.component(.weekday, from: now)) ?? .monday
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        if let next = store.nextRoutine(fromWeekday: weekday, hour: hour, minute: minute),
           next.type == .strength {
            return next
        }
        return store.routines.first { $0.type == .strength }
    }

    private func start() {
        let name = simulate ? "Strength Demo" : (nextRoutine?.name ?? "Strength")
        // No routine id under simulate (the demo isn't a saved routine → nothing to persist).
        manager.start(cards: sessionCards, routineId: simulate ? nil : nextRoutine?.id, routineName: name)
    }

    /// A short scripted strength session for the Simulator: two exercises with a brief rest
    /// between (to show the rest ring) and a plank, so the whole flow plays out quickly.
    static var demoCards: [WorkoutCard] {
        // Rests are long enough that a (slow) UITest reliably taps "Skip rest" before they elapse;
        // the demo is meant to be skipped through, so this doesn't slow a real run-through.
        [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 10)),
        ]
    }
}

/// B0 — pre-session for strength: the routine name and exercise count, one Start. Strength blue.
struct StrengthLaunchView: View {
    let routine: Routine?
    let exerciseCount: Int
    let onStart: () -> Void

    var body: some View {
        ZStack {
            if exerciseCount > 0 { WatchTheme.strengthField.ignoresSafeArea() }
            content
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 10) {
            if exerciseCount > 0 {
                Spacer(minLength: 0)
                Image(systemName: "dumbbell.fill")
                    .font(.title3)
                    .foregroundStyle(WatchTheme.strength)
                VStack(spacing: 3) {
                    Text("UP NEXT")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(routine?.name ?? "Strength")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text("Strength · \(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onStart) {
                    Text("Start")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.strength)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No session scheduled")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Create a strength routine on your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
    }
}
