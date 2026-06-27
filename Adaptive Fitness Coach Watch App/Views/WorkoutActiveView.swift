import SwiftUI
import AdaptiveCore

/// A2 / A3 — the core loop. One state fills the screen: a phase label (WARM UP / RUN / WALK /
/// COOL DOWN), a direction glyph, and the live interval timer, over a green (work) or amber
/// (recover) field. These screens are confirmation, not instruction — the haptics lead, the
/// screen reassures (N5). A small End control is the one deliberate affordance: every real
/// workout needs a way to stop (and to end the underlying HKWorkoutSession cleanly).
struct WorkoutActiveView: View {
    let manager: WorkoutSessionManager

    @State private var confirmingEnd = false

    private var phase: IntervalPhase? { manager.currentPhase }
    private var isRun: Bool { phase?.isRun ?? false }
    private var tint: Color { WorkoutColors.tint(for: phase) }

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
        ZStack {
            tint.opacity(0.22).ignoresSafeArea()

            VStack(spacing: 2) {
                // Top: HR · progress · session clock
                HStack {
                    HeartRateView(bpm: manager.currentHeartRate)
                    Spacer()
                    if let progressText {
                        Text(progressText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(manager.sessionElapsed.clockString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                // Center: phase label + glyph + interval timer
                Image(systemName: isRun ? "arrow.up" : "arrow.down")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(phaseLabel)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(manager.intervalElapsed.clockString)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()

                Spacer(minLength: 0)

                // Bottom: zone bar + unobtrusive End control
                ZoneBarView(currentZoneIndex: manager.currentZoneIndex, targetZoneIndex: manager.targetZone)
                Button("End", role: .destructive) { confirmingEnd = true }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            // A4 banner overlays the top when an adaptation occurs.
            if let message = manager.adaptationMessage {
                VStack {
                    AdaptationBannerView(message: message)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isRun)
        .animation(.easeInOut(duration: 0.25), value: manager.adaptationMessage)
        .confirmationDialog("End this run?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End workout", role: .destructive) { manager.endManually() }
            Button("Keep going", role: .cancel) {}
        }
    }
}
