import SwiftUI

/// The rows never *looked* tappable — this makes them *feel* tappable: a brief dim+settle
/// on touch teaches "these respond" after one tap, without adding chrome to every card.
///
/// (The custom SwipeableRow that used to live here was retired when the Food day screen
/// moved to a native List: `swipeActions` now provides the drag mechanics, and the delete
/// confirmation anchors to its row instead of presenting over the gauge.)
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
