import SwiftUI

/// A4 — the adaptation moment. One calm line, no alert, no "why". It appears for a few
/// seconds when the plan bends to the body, then fades. The session should feel like it is
/// breathing with the user, not correcting an error (Q5). The normal switch haptic is the
/// only other cue — no extra buzz.
struct AdaptationBannerView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption2.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
