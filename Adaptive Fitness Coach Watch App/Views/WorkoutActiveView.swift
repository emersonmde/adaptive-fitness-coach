import SwiftUI
import AdaptiveCore

/// A2 / A3 — the core loop. One state fills the screen: a verb (RUN / WALK), a direction
/// glyph, and the live interval timer, over a green (work) or amber (recover) field. These
/// screens are confirmation, not instruction — the haptics lead, the screen reassures (N5).
struct WorkoutActiveView: View {
    let manager: WorkoutSessionManager

    private var phase: IntervalPhase? { manager.currentPhase }
    private var isRun: Bool { phase?.isRun ?? false }
    private var tint: Color { WorkoutColors.tint(for: phase) }

    var body: some View {
        ZStack {
            tint.opacity(0.22).ignoresSafeArea()

            VStack(spacing: 2) {
                // Top: HR + session clock
                HStack {
                    HeartRateView(bpm: manager.currentHeartRate)
                    Spacer()
                    Text(manager.sessionElapsed.clockString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                // Center: verb + glyph + interval timer
                Image(systemName: isRun ? "arrow.up" : "arrow.down")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(isRun ? "RUN" : "WALK")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                Text(manager.intervalElapsed.clockString)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()

                Spacer(minLength: 0)

                // Bottom: zone bar
                ZoneBarView(currentZoneIndex: manager.currentZoneIndex, targetZoneIndex: 2)
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
    }
}
