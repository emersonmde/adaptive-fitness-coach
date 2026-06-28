import SwiftUI
import AdaptiveCore

/// Pages the strength session like the native Workout app, as three swipe pages with the dots as
/// the discoverability cue:
///   ◀ Controls (End)  ·  ● Set (the glance, default)  ·  Exercise ▶ (form demo + adjust weight)
///
/// The middle page is a pure glance — only what you act on *during* a set (movement, reps, set
/// progress, HR). Setup you do once — choosing the weight, checking the form — lives on the
/// Exercise page so it never clutters the glance, mirroring how the run screen keeps End off its
/// metrics page.
struct StrengthSessionPager: View {
    let manager: StrengthSessionManager
    @State private var selection = Page.glance

    private enum Page { case controls, glance, exercise }

    var body: some View {
        TabView(selection: $selection) {
            StrengthControlsView(manager: manager).tag(Page.controls)
            StrengthGlanceView(manager: manager) { withAnimation { selection = .exercise } }
                .tag(Page.glance)
            ExerciseDetailView(manager: manager).tag(Page.exercise)
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

/// ● The glance — a deep-blue field, a top status row (HR · "n of N" · live clock), and one
/// dominant element (the rep count, or a hold ring). Set progress shows as a segmented pip row —
/// the strength analogue of the run's zone bar. The weight reads out as a chip that jumps to the
/// Exercise page to adjust; the bottom stays open for the P2 fatigue/effort signal.
struct StrengthGlanceView: View {
    let manager: StrengthSessionManager
    /// Jump to the Exercise page (form demo + weight adjust).
    let showExercise: () -> Void

    private var exercise: Exercise? { manager.currentExercise }
    private var item: StrengthExerciseItem? { manager.currentItem }

    var body: some View {
        ZStack {
            WatchTheme.strengthField.ignoresSafeArea()

            VStack(spacing: 6) {
                statusRow

                Spacer(minLength: 0)

                if let exercise, let item {
                    Text(exercise.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if item.isHold {
                        HoldRingView(seconds: item.holdSeconds ?? 30) { manager.completeSet() }
                            .padding(.top, 2)
                        SetPipsView(total: manager.setsInCurrentExercise, currentSet: manager.currentSet)
                            .padding(.top, 4)
                    } else {
                        repHero(item)
                        weightChip(item)
                        SetPipsView(total: manager.setsInCurrentExercise, currentSet: manager.currentSet)
                            .padding(.top, 4)
                    }
                } else {
                    ProgressView().tint(WatchTheme.strength)
                }

                Spacer(minLength: 0)

                if let item, !item.isHold {
                    DoneSetButton { manager.completeSet() }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .animation(.easeInOut(duration: 0.25), value: manager.currentIndex)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: manager.currentSet)
    }

    /// Top row: live HR (pinned left) and "n of N" exercise progress (centered). The top-right
    /// corner is left clear for watchOS's own clock — and there's no session clock here since
    /// strength is rep-governed, not time-governed like a run (total time lands on the summary).
    private var statusRow: some View {
        ZStack {
            HStack {
                HeartRateView(bpm: manager.currentHeartRate)
                Spacer()
            }
            Text("\(manager.currentIndex + 1) of \(manager.exercises.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding(.horizontal, 2)
    }

    /// The rep prescription as one dominant number — the run timer's analogue.
    private func repHero(_ item: StrengthExerciseItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(item.reps ?? 0)")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("REPS")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }

    /// Read-only load with a chevron: shows which dumbbell to grab and taps through to adjust.
    /// Bodyweight shows a plain label (nothing to adjust).
    @ViewBuilder private func weightChip(_ item: StrengthExerciseItem) -> some View {
        if let weight = item.seedWeight {
            Button(action: showExercise) {
                HStack(spacing: 4) {
                    Text(weight.displayString())
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .foregroundStyle(WatchTheme.strength)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(WatchTheme.strength.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        } else {
            Text("Bodyweight")
                .font(.footnote.weight(.medium))
                .foregroundStyle(WatchTheme.textSecondary)
                .padding(.top, 4)
        }
    }
}

/// ▶ The Exercise page — setup for the current movement: the form demo (tap to bounce; the
/// future home of tap-to-play animations) and the ± weight adjust, plus a prescription summary.
/// A reference page, so it scrolls.
struct ExerciseDetailView: View {
    let manager: StrengthSessionManager

    /// Dumbbells commonly step in 5 lb; the seed is conservative and the user nudges from there.
    private let step = 5.0

    private var exercise: Exercise? { manager.currentExercise }
    private var item: StrengthExerciseItem? { manager.currentItem }

    var body: some View {
        ZStack {
            WatchTheme.strengthField.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    if let exercise, let item {
                        FormDemoView(formDemo: exercise.formDemo)
                            .frame(height: 84)

                        Text(exercise.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        if let weight = item.seedWeight {
                            VStack(spacing: 6) {
                                Text("WEIGHT")
                                    .font(.caption2.weight(.semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(WatchTheme.textSecondary)
                                HStack(spacing: 12) {
                                    weightButton("minus") { adjust(-step) }
                                    Text(weight.displayString())
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(WatchTheme.strength)
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                        .frame(minWidth: 70)
                                    weightButton("plus") { adjust(step) }
                                }
                            }
                        }

                        Text(prescription(item, exercise: exercise))
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .padding(.top, 2)
                    } else {
                        ProgressView().tint(WatchTheme.strength)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func adjust(_ delta: Double) {
        withAnimation(.snappy) { manager.adjustWeight(byPounds: delta) }
    }

    private func weightButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.strength)
        .clipShape(Circle())
    }

    private func prescription(_ item: StrengthExerciseItem, exercise: Exercise) -> String {
        if item.isHold {
            return "\(item.sets) sets · \(Int(item.holdSeconds ?? 0))s hold"
        }
        return "\(item.sets) sets · \(item.reps ?? 0) reps"
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
            .frame(width: 92, height: 92)

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
                    .font(.system(size: 42))
                    .symbolEffect(.bounce, value: bounce)
                    .foregroundStyle(WatchTheme.strength)
                    .frame(width: 84, height: 84)
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
