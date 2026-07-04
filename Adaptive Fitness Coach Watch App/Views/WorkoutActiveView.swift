import SwiftUI
import AdaptiveCore

/// A2 / A3 — the core loop. One screen, pure glance: a phase label (WARM UP / RUN / WALK /
/// COOL DOWN), a direction glyph, and the live interval timer, over a green (work) or amber
/// (recover) field. Confirmation, not instruction — the haptics lead (N5). No controls clutter
/// the glance screen: End lives on a swipe-away controls page; adaptations show as a brief
/// non-occluding cue at the bottom, never a sentence to read mid-stride.
struct WorkoutActiveView: View {
    let manager: WorkoutSessionManager

    @State private var switchPulse = false
    @State private var mismatchPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: IntervalPhase? { manager.currentPhase }
    private var isRun: Bool { phase?.isRun ?? false }
    private var tint: Color { WorkoutColors.tint(for: phase) }

    /// True in the final few seconds before a switch — when the timer brightens/pulses so the
    /// haptic isn't the user's only warning.
    private var nearingSwitch: Bool {
        let remaining = manager.intervalRemaining
        return manager.intervalTarget > 0 && remaining > 0 && remaining <= 5
    }

    /// Distinct labels so warmup/cooldown walks don't read as mid-session recovery walks.
    private var phaseLabel: String {
        switch phase {
        case .run: "RUN"
        case .warmupWalk: "WARM UP"
        case .cooldownWalk: "COOL DOWN"
        case .walk, .none: "WALK"
        }
    }

    /// "n of N" run-interval progress, shown only during the repeating run/walk cycles.
    private var progressText: String? {
        guard let phase, phase == .run || phase == .walk, manager.totalRunIntervals > 0 else { return nil }
        let current = min(manager.intervalsCompleted + (isRun ? 1 : 0), manager.totalRunIntervals)
        return "\(current) of \(manager.totalRunIntervals)"
    }

    var body: some View {
        content
            .pagedWorkoutBackground(WorkoutColors.field(for: phase))
    }

    private var content: some View {
        VStack(spacing: 2) {
                // Top: workout clock · progress · HR. Two glyph-anchored primary metrics at
                // full weight flanking a quiet center. The workout clock sits top-LEFT — the
                // far corner from the (unremovable) system clock — so the two times can't be
                // confused; the stopwatch and heart glyphs identify each number before it's
                // read. "n of N" stays secondary: ambient context, not a metric.
                HStack {
                    SessionClockView(elapsed: manager.sessionElapsed)
                    Spacer()
                    if let progressText {
                        Text(progressText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HeartRateView(bpm: manager.currentHeartRate)
                }

                Spacer(minLength: 0)

                // Center: phase label + glyph + interval timer. When cadence says the user is
                // still running through a WALK phase, the instruction itself throbs — motion
                // is the compliance channel, the color stays the instruction (a glance that
                // misread amber as green can't misread a pulsing word).
                Image(systemName: isRun ? "arrow.up" : "arrow.down")
                    .font(.headline)
                    .foregroundStyle(tint)
                    .scaleEffect(mismatchPulse ? 1.25 : 1.0)
                Text(phaseLabel)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .scaleEffect(mismatchPulse ? 1.12 : 1.0)
                // The interval timer counts DOWN (remaining, not elapsed): mid-effort the only
                // question is "how much longer" — the count-up job belongs to the session clock
                // in the corner. It doubles as the pre-switch cue: in the final seconds it
                // shifts to the phase color and gently pulses, so the upcoming switch is
                // anticipated visually (N5) without adding another stacked line to the bottom.
                Text(manager.intervalRemaining.clockString)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(nearingSwitch ? tint : Color.white)
                    .scaleEffect(nearingSwitch && switchPulse && !reduceMotion ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: nearingSwitch)

                Spacer(minLength: 0)

                // Bottom: zone bar, then a brief directional adaptation cue (non-occluding) in
                // the space where the End control used to sit.
                ZoneBarView(currentZoneIndex: manager.currentZoneIndex, targetZoneIndex: manager.targetZone,
                            emphasize: manager.gaitMismatch)

                ZStack {
                    // Reserve a constant slot so the layout doesn't jump when the cue appears.
                    Color.clear.frame(height: 20)
                    if let event = manager.adaptationEvent {
                        AdaptationCue(event: event)
                    } else if phase == .warmupWalk {
                        // Warmup never shows adaptation cues, so the slot hosts the skip
                        // control: cadence detection usually ends the warmup by itself, but a
                        // tap works when motion data isn't available (N6) or the user just
                        // wants to go. Gone once the first run starts — the glance stays clean.
                        Button(action: manager.skipWarmup) {
                            Text("Start Run")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(WatchTheme.run.opacity(0.2)))
                                .foregroundStyle(WatchTheme.run)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 3)
            }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.25), value: isRun)
        .animation(.easeInOut(duration: 0.3), value: manager.adaptationEvent)
        .onChange(of: nearingSwitch) { _, near in
            if near && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { switchPulse = true }
            } else {
                withAnimation(.default) { switchPulse = false }
            }
        }
        .onChange(of: manager.gaitMismatch, initial: true) { _, mismatched in
            if mismatched && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { mismatchPulse = true }
            } else {
                withAnimation(.default) { mismatchPulse = false }
            }
        }
    }
}
