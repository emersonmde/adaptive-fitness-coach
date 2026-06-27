import SwiftUI

/// The one focal CTA: a lime fill with dark text and a single soft accent glow. Dark-on-neon
/// keeps it highly legible (~14:1). The glow is suppressed under Reduce Motion / when not the
/// focal element. Use exactly one per screen.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var glow: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: Theme.accent.opacity(glow && !reduceMotion ? 0.35 : 0),
                radius: 16, y: 4)
    }
}

/// A quiet secondary text link (e.g. "Let AI draft a week"), accent-colored, no fill.
struct SecondaryLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
