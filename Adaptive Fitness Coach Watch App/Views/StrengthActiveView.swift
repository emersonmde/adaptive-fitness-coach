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

/// B1/B2 — the current exercise card. Built to read like the run screen: a deep-blue field
/// grounds the glance, a top status row carries HR · exercise progress · session clock, and one
/// dominant number (reps, or a hold ring) is the hero. Set progress shows as a segmented pip row
/// — the strength analogue of the run's zone bar. The form diagram (B1) collapses once learned
/// (B2). Strength is blue throughout; the watch never uses the phone's brand accent.
struct ExerciseCardView: View {
    let manager: StrengthSessionManager
    @State private var showDemo = true
    @AppStorage("strengthHideDemos") private var hideDemosByDefault = false

    private var exercise: Exercise? { manager.currentExercise }
    private var item: StrengthExerciseItem? { manager.currentItem }

    var body: some View {
        ZStack {
            // Colored ground: the blue telegraphs "strength" before any word is read.
            WatchTheme.strengthField.ignoresSafeArea()

            VStack(spacing: 5) {
                statusRow

                ScrollView {
                    VStack(spacing: 6) {
                        if let exercise, let item {
                            if showDemo {
                                FormDemoView(formDemo: exercise.formDemo)
                                    .frame(height: 46)
                                    .transition(.opacity.combined(with: .scale))
                            }

                            Text(exercise.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)

                            if item.isHold {
                                HoldRingView(seconds: item.holdSeconds ?? 30) { manager.completeSet() }
                                    .padding(.vertical, 2)
                            } else {
                                RepHero(item: item, manager: manager)
                            }

                            SetPipsView(total: manager.setsInCurrentExercise, currentSet: manager.currentSet)
                                .padding(.top, 1)

                            if !item.isHold {
                                DoneSetButton { manager.completeSet() }
                            }

                            demoToggle
                        } else {
                            ProgressView().tint(WatchTheme.strength)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .animation(.easeInOut(duration: 0.25), value: manager.currentIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: manager.currentSet)
        .onAppear { showDemo = !hideDemosByDefault }
    }

    /// Top row, mirroring the run screen: live HR · "n of N" exercise progress · session clock.
    private var statusRow: some View {
        HStack {
            HeartRateView(bpm: manager.currentHeartRate)
            Spacer()
            Text("\(manager.currentIndex + 1) of \(manager.exercises.count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(WatchTheme.textSecondary)
            Spacer()
            SessionClock(start: manager.sessionStartDate)
        }
        .padding(.horizontal, 2)
    }

    private var demoToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDemo.toggle()
                // Remember the choice: once the movement is learned and the demo hidden, the card
                // stays compact (everything visible at a glance) on every later exercise (B2).
                hideDemosByDefault = !showDemo
            }
        } label: {
            Label(showDemo ? "Hide demo" : "Show demo", systemImage: showDemo ? "chevron.up" : "figure.strengthtraining.traditional")
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
    }
}

/// The rep prescription as one dominant number (the run timer's analogue): a big rounded rep
/// count with a quiet label, and the load as a refined ± chip beneath it.
private struct RepHero: View {
    let item: StrengthExerciseItem
    let manager: StrengthSessionManager

    /// Dumbbells commonly step in 5 lb; the seed is conservative and the user nudges from there.
    private let step = 5.0

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(item.reps ?? 0)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("REPS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(WatchTheme.textSecondary)
            }

            if let weight = item.seedWeight {
                HStack(spacing: 10) {
                    weightButton("minus") { adjust(-step) }
                    Text(weight.displayString())
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(WatchTheme.strength)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 64)
                    weightButton("plus") { adjust(step) }
                }
            } else {
                Text("Bodyweight")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
    }

    private func adjust(_ delta: Double) {
        withAnimation(.snappy) { manager.adjustWeight(byPounds: delta) }
    }

    private func weightButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.strength)
        .clipShape(Circle())
    }
}

/// Segmented set-progress — the strength analogue of the run's zone bar. One capsule per set:
/// completed sets are filled and dim, the current set dominates (full color, taller, soft glow),
/// upcoming sets recede. Reading "where am I in this exercise" at a glance, no number needed.
struct SetPipsView: View {
    let total: Int
    /// 1-based current set.
    let currentSet: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, total), id: \.self) { slot in
                let isDone = slot < currentSet - 1
                let isCurrent = slot == currentSet - 1
                Capsule()
                    .fill(WatchTheme.strength.opacity(isCurrent ? 1.0 : (isDone ? 0.55 : 0.18)))
                    .frame(width: isCurrent ? 22 : 14, height: isCurrent ? 6 : 5)
                    .shadow(color: isCurrent ? WatchTheme.strength.opacity(0.6) : .clear, radius: 4)
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Set")
        .accessibilityValue("\(currentSet) of \(total)")
    }
}

/// A live session clock that ticks from the session start. Uses `TimelineView` so the manager
/// doesn't need a tick loop just to drive the seconds (the strength session is user-advanced).
private struct SessionClock: View {
    let start: Date?

    var body: some View {
        Group {
            if let start {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(context.date.timeIntervalSince(start).clockString)
                }
            } else {
                Text("0:00")
            }
        }
        .font(.caption2)
        .foregroundStyle(WatchTheme.textSecondary)
        .monospacedDigit()
    }
}

/// Isometric hold as a premium countdown ring: tap to run it, the ring drains as time elapses,
/// and it completes the set on its own at zero (or the user can finish early). The ring is the
/// hero — the strength counterpart to the rep number.
struct HoldRingView: View {
    let seconds: TimeInterval
    let onComplete: () -> Void

    @State private var remaining: TimeInterval
    @State private var running = false
    @State private var ticker: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(seconds: TimeInterval, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.onComplete = onComplete
        _remaining = State(initialValue: seconds)
    }

    private var progress: Double { seconds > 0 ? remaining / seconds : 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(WatchTheme.strength.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WatchTheme.strength, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: WatchTheme.strength.opacity(running ? 0.5 : 0), radius: 5)
                    .animation(.linear(duration: reduceMotion ? 0 : 1), value: remaining)
                Text(remaining.clockString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 96, height: 96)

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
/// the eventual tap-to-play animation. The symbol sits on a faint blue disc so it reads as a
/// deliberate diagram, not a stray glyph. `.diagram`/`.animation` are reserved for real assets.
struct FormDemoView: View {
    let formDemo: FormDemo
    @State private var bounce = 0

    var body: some View {
        Group {
            switch formDemo {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 30))
                    .symbolEffect(.bounce, value: bounce)
                    .foregroundStyle(WatchTheme.strength)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle().fill(WatchTheme.strength.opacity(0.12))
                            .overlay(Circle().strokeBorder(WatchTheme.strength.opacity(0.25), lineWidth: 1))
                    )
            case let .diagram(name), let .animation(name):
                // Future assets; until they ship, fall back to a neutral figure placeholder.
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(WatchTheme.strength)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { bounce += 1 }
    }
}
