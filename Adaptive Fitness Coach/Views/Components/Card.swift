import SwiftUI

/// The base matte-dark surface for the phone UI: a rounded `surface1` panel with a hairline
/// border (borders read better than shadows on dark). This is the canvas; Liquid Glass is
/// reserved as a focal accent elsewhere (the Up-Next hero), not on every card.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
