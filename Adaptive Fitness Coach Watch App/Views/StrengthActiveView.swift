import SwiftUI
import AdaptiveCore

/// Pages the strength session like the native Workout app: a swipe-away **controls** page (End)
/// and the **card** page (the current exercise). Starts on the card so the glance stays pure.
struct StrengthSessionPager: View {
    let manager: StrengthSessionManager
    @State private var selection = Page.card

    private enum Page { case controls, card }

    var body: some View {
        TabView(selection: $selection) {
            StrengthControlsView(manager: manager).tag(Page.controls)
            ExerciseCardView(manager: manager).tag(Page.card)
        }
        .tabViewStyle(.page)
    }
}

/// The controls page: End the strength workout (ends the underlying HKWorkoutSession cleanly).
struct StrengthControlsView: View {
    let manager: StrengthSessionManager

    var body: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                manager.endManually()
            } label: {
                Label("End Workout", systemImage: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .tint(WatchTheme.hot)

            Text("Swipe back to your set")
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding()
    }
}

/// B1/B2 — the current exercise card: form diagram, prescription, proposed weight (± adjust),
/// "set N of M", and the Done-set action. The form diagram (an SF Symbol placeholder for now)
/// can be collapsed once the movement is learned (B2 compact). Strength's color is blue.
struct ExerciseCardView: View {
    let manager: StrengthSessionManager
    @State private var showDemo = true
    @AppStorage("strengthHideDemos") private var hideDemosByDefault = false

    private var exercise: Exercise? { manager.currentExercise }
    private var item: StrengthExerciseItem? { manager.currentItem }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header

                if let exercise, let item {
                    if showDemo {
                        FormDemoView(formDemo: exercise.formDemo)
                            .frame(height: 64)
                            .transition(.opacity)
                    }

                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    if item.isHold {
                        HoldCardBody(seconds: item.holdSeconds ?? 30) { manager.completeSet() }
                    } else {
                        RepCardBody(item: item, manager: manager)
                    }

                    demoToggle
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .onAppear { showDemo = !hideDemosByDefault }
    }

    private var header: some View {
        HStack {
            Text("\(manager.currentIndex + 1) of \(manager.exercises.count)")
            Spacer()
            Text("Set \(manager.currentSet)/\(manager.setsInCurrentExercise)")
                .foregroundStyle(WatchTheme.strength)
        }
        .font(.caption2)
        .foregroundStyle(WatchTheme.textSecondary)
    }

    private var demoToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showDemo.toggle() }
        } label: {
            Text(showDemo ? "Hide demo" : "Show demo")
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

/// Rep-based card body: the set/rep/weight prescription, ± weight adjust, and Done set.
private struct RepCardBody: View {
    let item: StrengthExerciseItem
    let manager: StrengthSessionManager

    /// Dumbbells commonly step in 5 lb; the seed is conservative and the user nudges from there.
    private let step = 5.0

    var body: some View {
        VStack(spacing: 8) {
            Text("\(item.reps ?? 0) reps")
                .font(.title3.bold())
                .foregroundStyle(.white)

            if let weight = item.seedWeight {
                HStack(spacing: 14) {
                    weightButton(systemName: "minus") { manager.adjustWeight(byPounds: -step) }
                    Text(weight.displayString())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WatchTheme.strength)
                        .frame(minWidth: 70)
                    weightButton(systemName: "plus") { manager.adjustWeight(byPounds: step) }
                }
            } else {
                Text("Bodyweight")
                    .font(.subheadline)
                    .foregroundStyle(WatchTheme.textSecondary)
            }

            DoneSetButton { manager.completeSet() }
        }
    }

    private func weightButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.strength)
        .clipShape(Circle())
    }
}

/// Isometric card body: a hold timer. Tap to run the countdown; it completes the set on its own
/// at zero (haptic), or the user can finish early. Progression is identical to a rep set.
private struct HoldCardBody: View {
    let seconds: TimeInterval
    let onComplete: () -> Void

    @State private var remaining: TimeInterval
    @State private var running = false
    @State private var ticker: Task<Void, Never>?

    init(seconds: TimeInterval, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.onComplete = onComplete
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(remaining.clockString)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(running ? WatchTheme.strength : .white)

            if running {
                Button("Done early") { complete() }
                    .buttonStyle(.bordered)
                    .tint(WatchTheme.strength)
            } else {
                Button {
                    start()
                } label: {
                    Label("Start hold", systemImage: "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.strength)
            }
        }
        .onDisappear { ticker?.cancel() }
    }

    private func start() {
        running = true
        remaining = seconds
        ticker = Task {
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining = max(0, remaining - 1)
            }
            if !Task.isCancelled { complete() }
        }
    }

    private func complete() {
        ticker?.cancel()
        running = false
        onComplete()
    }
}

/// The primary "Done set" action — the deliberate, haptic-led advance through the sequence (N5).
private struct DoneSetButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Done set", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.strength)
        .padding(.top, 2)
    }
}

/// Renders a `FormDemo`. P1 only carries `.symbol`; a tap gives a small bounce — a cheap nod to
/// the eventual tap-to-play animation. `.diagram`/`.animation` are reserved for real assets.
struct FormDemoView: View {
    let formDemo: FormDemo
    @State private var bounce = 0

    var body: some View {
        Group {
            switch formDemo {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 44))
                    .symbolEffect(.bounce, value: bounce)
            case let .diagram(name), let .animation(name):
                // Future assets; until they ship, fall back to a neutral figure placeholder.
                Image(name)
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(WatchTheme.strength)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { bounce += 1 }
    }
}
