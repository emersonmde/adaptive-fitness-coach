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
            // During a rest the *glance page* becomes the rest card — inside the pager, not
            // replacing it, so End stays one swipe away for the whole rest ("always an exit",
            // DESIGN-PRINCIPLES #13; an earlier build swapped the entire TabView for RestView
            // and wedged the user until READY). Rest state is manager-owned and resets per
            // card, so back-to-back rests just work.
            Group {
                if manager.activity == .rest {
                    RestView(manager: manager)
                } else {
                    StrengthGlanceView(manager: manager) { withAnimation(WatchTheme.Motion.settle) { selection = .exercise } }
                }
            }
            .tag(Page.glance)
            // The Exercise page is setup for the *current* movement; a rest card has none, so
            // the page drops out rather than showing an eternal spinner. Dropping it also
            // means a swipe right from the rest card can't land anywhere confusing.
            if manager.activity != .rest {
                ExerciseDetailView(manager: manager).tag(Page.exercise)
            }
        }
        .tabViewStyle(.page)
        .onChange(of: manager.activity) { _, activity in
            // Snap home when a rest begins: the recovery ring should greet the user wherever
            // they were, and the selection must leave the Exercise page before it vanishes.
            if activity == .rest { withAnimation(WatchTheme.Motion.settle) { selection = .glance } }
        }
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

    /// Crown-bound mirror of `manager.repsPending` (the crown API wants a Double binding).
    @State private var crownValue: Double = 0
    @FocusState private var crownFocused: Bool

    private var exercise: Exercise? { manager.currentExercise }
    private var item: StrengthExerciseItem? { manager.currentItem }

    var body: some View {
        VStack(spacing: 6) {
            statusRow

            Spacer(minLength: 0)

            if let exercise, let item {
                Text(exercise.name)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if item.isHold {
                    HoldRingView(manager: manager)
                        .padding(.top, 2)
                } else {
                    repHero
                    weightChip(item)
                }
            } else {
                ProgressView().tint(WatchTheme.strength)
            }

            Spacer(minLength: 0)

            // Set pips: this exercise's sets across the block (real information — the
            // strength analogue of the run's "n of N"), in the reserved bottom slot.
            setPips

            if let item, !item.isHold {
                DoneSetButton { manager.completeSet() }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .pagedWorkoutBackground(WatchTheme.strengthField)
        .animation(WatchTheme.Motion.settle, value: manager.currentIndex)
        .onChange(of: manager.currentIndex) { _, _ in crownValue = Double(manager.repsPending) }
        .onAppear { crownValue = Double(manager.repsPending) }
    }

    /// Per-set pips for the current exercise: filled = done, bright = current, dim = ahead.
    @ViewBuilder private var setPips: some View {
        let pos = manager.currentExerciseSetPosition
        if pos.total > 1 {
            HStack(spacing: 5) {
                ForEach(1...pos.total, id: \.self) { set in
                    Capsule()
                        .fill(WatchTheme.strength.opacity(set < pos.current ? 0.9 : (set == pos.current ? 0.5 : 0.18)))
                        .frame(width: set == pos.current ? 18 : 10, height: 4)
                }
            }
            .padding(.bottom, 2)
            .accessibilityElement()
            .accessibilityLabel("Set \(pos.current) of \(pos.total)")
        } else {
            Color.clear.frame(height: 4)
        }
    }

    /// Top row: live HR (pinned left) and "n of N" exercise progress (centered). The top-right
    /// corner is left clear for watchOS's own clock — and there's no session clock here since
    /// strength is rep-governed, not time-governed like a run (total time lands on the summary).
    private var statusRow: some View {
        let pos = manager.exercisePosition
        return ZStack {
            HStack {
                HeartRateView(bpm: manager.currentHeartRate)
                Spacer()
            }
            Text("\(pos.current) of \(pos.total)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding(.horizontal, 2)
    }

    /// The rep number as one dominant, **live** element: it starts at the prescription and
    /// the Digital Crown adjusts it before "Done set" — this is how the app learns the reps
    /// actually done with zero added friction on a hit-the-prescription set. The tiny crown
    /// glyph is the affordance; color stays out of it (color = instruction).
    private var repHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(manager.repsPending)")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                Text("REPS")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(WatchTheme.textSecondary)
                Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise.fill")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textSecondary.opacity(0.7))
            }
        }
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            // Headroom above the prescription, not a lid on it: an athlete repping 20 when 10
            // was prescribed is producing exactly the progression evidence the app exists to
            // capture — the old `prescription + 5` cap silently discarded it. Double the
            // prescription (with a 30-rep floor for low prescriptions) covers any plausible
            // set without turning the crown into an endless dial.
            through: Double(max(30, (item?.reps ?? 0) * 2)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, value in
            manager.repsPending = Int(value.rounded())
        }
        .onAppear { crownFocused = true }
        .accessibilityElement()
        .accessibilityLabel("Reps this set")
        .accessibilityValue("\(manager.repsPending)")
        .accessibilityAdjustableAction { direction in
            // Keep the crown-bound mirror in step: adjusting only `repsPending` would leave
            // `crownValue` at the old detent, so the next crown turn snaps the count back.
            switch direction {
            case .increment: manager.repsPending += 1
            case .decrement: manager.repsPending = max(0, manager.repsPending - 1)
            @unknown default: break
            }
            crownValue = Double(manager.repsPending)
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
                            adjustRow(title: "WEIGHT", value: weight.displayString(),
                                      onMinus: { adjust(-step) }, onPlus: { adjust(step) })
                        }

                        // Reps are adjustable for rep-based moves (not holds) — bump them when the
                        // prescribed count feels easy; it persists as the new seed (N7).
                        if let reps = item.reps {
                            adjustRow(title: "REPS", value: "\(reps)",
                                      onMinus: { adjustReps(-1) }, onPlus: { adjustReps(1) })
                        }

                        Text(prescription(item, exercise: exercise))
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .padding(.top, 2)

                        ExerciseInfoView(exercise: exercise)
                            .padding(.top, 6)
                    } else {
                        ProgressView().tint(WatchTheme.strength)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .pagedWorkoutBackground(WatchTheme.strengthField)
    }

    private func adjust(_ delta: Double) {
        withAnimation(WatchTheme.Motion.snap) { manager.adjustWeight(byPounds: delta) }
    }

    private func adjustReps(_ delta: Int) {
        withAnimation(WatchTheme.Motion.snap) { manager.adjustReps(by: delta) }
    }

    /// A labelled ± row — the shared layout for the WEIGHT and REPS adjusters.
    private func adjustRow(title: String, value: String,
                           onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.textSecondary)
            HStack(spacing: 12) {
                adjustButton("minus", action: onMinus)
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(WatchTheme.strength)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 70)
                adjustButton("plus", action: onPlus)
            }
        }
    }

    private func adjustButton(_ systemName: String, action: @escaping () -> Void) -> some View {
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
        if item.isHold { return "\(Int(item.holdSeconds ?? 0))s hold" }
        return "\(item.reps ?? 0) reps"
    }
}

/// A rest card — the glance page during recovery between sets, rendered from manager state
/// (the manager owns the clock and the `RestRecoveryModel`). Lives *inside* the session pager
/// (controls stay one swipe away), so it uses the paged background idiom like its siblings.
///
/// Two honest modes, one ring, one variable (DESIGN-PRINCIPLES): with heart rate on an
/// adaptive rest, a **strength-blue ring fills** with recovery progress while the falling HR
/// is the hero — the READY moment closes the ring, flips the label, and buzzes. Fixed rests
/// (or no HR — N6) render the classic **heat-amber ring draining** with time as the hero.
/// Blue means recovery; amber means time; never both arcs.
struct RestView: View {
    let manager: StrengthSessionManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hrMode: Bool { manager.restUsesHeartRate }
    private var ready: Bool { manager.restIsReady }
    private var ringColor: Color { hrMode ? WatchTheme.strength : WatchTheme.heat }

    var body: some View {
        VStack(spacing: 12) {
            Text(ready ? "READY" : "REST")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(ready ? WatchTheme.strength : ringColor)
                .animation(WatchTheme.Motion.settle, value: ready)

            ZStack {
                Circle().stroke(ringColor.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: hrMode ? manager.restReadiness : timeFraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ready ? WatchTheme.strength.opacity(0.5) : .clear, radius: 5)
                    .animation(reduceMotion ? nil : WatchTheme.Motion.gentle, value: hrMode ? manager.restReadiness : timeFraction)

                if hrMode {
                    // The falling heart rate is the hero — watching it refill the ring is
                    // the point; the clock is ambient.
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(WatchTheme.hot)
                            Text(manager.currentHeartRate > 0 ? "\(Int(manager.currentHeartRate))" : "--")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(.white)
                        }
                        Text(manager.restRemaining.clockString)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                } else {
                    Text(manager.restRemaining.clockString)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 104, height: 104)

            if ready {
                Button {
                    manager.advance()
                } label: {
                    Label("Start next set", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.strength)
            } else {
                Button("Skip rest") { manager.skipRest() }
                    .buttonStyle(.bordered)
                    .tint(ringColor)
            }
        }
        .pagedWorkoutBackground(WatchTheme.strengthField)
        .animation(WatchTheme.Motion.settle, value: ready)
    }

    /// Time fraction remaining for the fallback ring (drains toward 0, like the old view).
    private var timeFraction: Double {
        guard let planned = manager.currentRestSeconds, planned > 0 else { return 0 }
        return min(max(manager.restRemaining / planned, 0), 1)
    }
}

/// Isometric hold as a premium countdown ring, rendered from manager state (the manager owns
/// the clock, so the actual seconds held feed progression). Tap to run it; it records and
/// advances on its own at zero, or "Done early" records what was actually held.
struct HoldRingView: View {
    let manager: StrengthSessionManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var planned: TimeInterval { manager.currentItem?.holdSeconds ?? 0 }
    private var progress: Double { planned > 0 ? manager.holdRemaining / planned : 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(WatchTheme.strength.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WatchTheme.strength, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: WatchTheme.strength.opacity(manager.holdRunning ? 0.5 : 0), radius: 5)
                    .animation(reduceMotion ? nil : WatchTheme.Motion.gentleLinear(1), value: manager.holdRemaining)
                Text(manager.holdRemaining.clockString)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)

            if manager.holdRunning {
                Button("Done early") { manager.completeHoldEarly() }
                    .buttonStyle(.bordered)
                    .tint(WatchTheme.strength)
            } else {
                Button {
                    manager.startHold()
                } label: {
                    Label("Start hold", systemImage: "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.strength)
            }
        }
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

/// The exercise help content on the Exercise page: how to perform the movement, the muscles it
/// works, what it's good for, and coaching tips. The form demo above it is the future home of an
/// animation/diagram; this is the text that teaches the movement (the same copy the iOS info sheet
/// shows). A reference block, so it lives on the scrollable Exercise page, never the glance (N5).
struct ExerciseInfoView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("HOW TO") {
                Text(exercise.howTo).foregroundStyle(.white.opacity(0.9))
            }
            if !exercise.muscleTags.isEmpty {
                section("WORKS") {
                    Text(exercise.muscleTags.map(\.capitalized).joined(separator: " · "))
                        .foregroundStyle(WatchTheme.strength)
                }
            }
            section("GOOD FOR") {
                Text(exercise.goodFor).foregroundStyle(.white.opacity(0.9))
            }
            if !exercise.tips.isEmpty {
                section("TIPS") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(exercise.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(WatchTheme.strength)
                                Text(tip).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.textSecondary)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
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
