import SwiftUI

/// An eyebrow label above a matte `Card` — the dark-mode replacement for a `Form` section,
/// used across the create/edit routine screens for a consistent custom look.
struct FieldSection<Content: View>: View {
    let title: String
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            Card(padding: padding) { content }
        }
    }
}
