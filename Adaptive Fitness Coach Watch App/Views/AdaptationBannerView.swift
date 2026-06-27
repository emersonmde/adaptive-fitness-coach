import SwiftUI
import AdaptiveCore

/// A4 — the adaptation moment, reimagined as a glanceable cue instead of a sentence to read.
///
/// A sentence banner over the metrics fails the core premise (follow the buzz, don't read the
/// watch mid-run — N5) and covers the HR/timer. Instead this is a tiny directional chip: a
/// chevron + one word, colored by direction (green = pushing, amber = easing), shown briefly at
/// the bottom edge where it occludes nothing. The full, readable detail lives in the post-run
/// summary, where there's time to read.
struct AdaptationCue: View {
    let event: AdaptationEvent

    private var pushing: Bool { event.action.increasesEffort }

    private var glyph: String { pushing ? "chevron.up.2" : "chevron.down.2" }

    private var word: String {
        switch event.action {
        case .shortenedRun: "EASING"
        case .lengthenedWalk: "RECOVER"
        case .extendedRun: "STRONG"
        case .shortenedWalk: "GO"
        }
    }

    private var color: Color { pushing ? WatchTheme.run : WatchTheme.walk }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.caption2.weight(.bold))
            Text(word)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .accessibilityLabel(event.message) // full sentence for VoiceOver only
    }
}
