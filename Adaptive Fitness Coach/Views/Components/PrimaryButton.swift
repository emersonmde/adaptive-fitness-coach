import SwiftUI

/// The one focal CTA. Deliberately NOT a flat neon fill (which reads as generic-fitness /
/// AI-slop): instead a dark, elevated capsule with a glowing accent edge and bright accent text,
/// plus the soft accent glow halo. The accent becomes a *glowing outline*, not a paint bucket —
/// premium and custom while keeping the green glow. Use exactly one per screen.
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
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface2, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentGlow.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.plain)
        .shadow(color: Theme.accent.opacity(glow && !reduceMotion ? 0.18 : 0), radius: 12, y: 4)
    }
}
