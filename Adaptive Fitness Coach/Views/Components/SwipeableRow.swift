import SwiftUI

/// Custom swipe actions styled like the row itself (native `swipeActions` renders
/// full-bleed slabs that fight the floating-card look, and only works in a List).
/// The mechanics mirror Notification Center: a short drag reveals a card-styled button
/// that stretches with the finger; past the commit threshold a haptic fires and release
/// performs the action. Leading = log again, trailing = delete (which only *requests* —
/// the confirm dialog stays between a flick and a permanent Health deletion).
struct SwipeableRow<Content: View>: View {
    let id: UUID
    @Binding var openRowID: UUID?
    let onRelog: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    /// Offset when the current drag began (an open row drags from its parked position).
    @State private var dragStart: CGFloat?
    /// Crossing the commit threshold mid-drag → one haptic tick, on arming only.
    @State private var pastCommit = false
    /// Decided on the first movement: horizontal-dominant → ours; vertical → the scroll
    /// view's. Even with `highPriorityGesture` we self-reject vertical movement so the
    /// ScrollView isn't starved of its drags.
    @State private var horizontalLatch: Bool?

    private let buttonWidth: CGFloat = 68
    private let gap: CGFloat = 8
    private var revealWidth: CGFloat { buttonWidth + gap }
    private let commitDistance: CGFloat = 180

    var body: some View {
        ZStack {
            // Leading action (revealed by dragging right).
            actionButton(
                title: "Log again", systemImage: "arrow.counterclockwise",
                tint: Theme.accent, alignment: .leading, revealed: offset
            ) {
                close()
                onRelog()
            }
            // Trailing action (revealed by dragging left).
            actionButton(
                title: "Delete", systemImage: "trash",
                tint: Theme.hot, alignment: .trailing, revealed: -offset
            ) {
                close()
                onDelete()
            }
            content
                .offset(x: offset)
        }
        // highPriority: plain and simultaneous variants both silently lose the recognizer
        // race to the ScrollView+Button stack (verified via hierarchy dump — the drag never
        // fired). The 18pt minimum keeps taps routing to the Button; the latch hands
        // vertical movement back to the scroll view.
        .highPriorityGesture(drag)
        .onChange(of: openRowID) {
            // Someone else opened (or everything was told to close) — park back at zero.
            if openRowID != id, offset != 0 { close() }
        }
    }

    /// One action, styled like the Card it hides behind: same corner radius and border,
    /// tinted icon+label, and it STRETCHES with the drag past its resting width.
    private func actionButton(
        title: String, systemImage: String, tint: Color,
        alignment: Alignment, revealed: CGFloat, action: @escaping () -> Void
    ) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 0) }
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .frame(width: max(buttonWidth, revealed - gap))
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .opacity(revealed > 8 ? min(1, Double((revealed - 8) / 40)) : 0)
        .accessibilityHidden(revealed < revealWidth * 0.6)   // VoiceOver uses the row's actions
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if horizontalLatch == nil {
                    horizontalLatch = abs(value.translation.width) > abs(value.translation.height)
                }
                guard horizontalLatch == true else { return }
                if dragStart == nil {
                    dragStart = offset
                    openRowID = id   // opening this row closes any other
                }
                let proposed = (dragStart ?? 0) + value.translation.width
                // Rubber-band past the commit point — the action is armed, not "more armed".
                if abs(proposed) > commitDistance {
                    let sign: CGFloat = proposed > 0 ? 1 : -1
                    offset = sign * (commitDistance + (abs(proposed) - commitDistance) * 0.22)
                } else {
                    offset = proposed
                }
                let nowPast = abs(proposed) > commitDistance
                if nowPast && !pastCommit { Theme.Haptics.commitTick() }   // arm only, never disarm
                pastCommit = nowPast
            }
            .onEnded { value in
                let wasOurs = horizontalLatch == true && dragStart != nil
                let landed = (dragStart ?? 0) + value.translation.width
                horizontalLatch = nil
                dragStart = nil
                pastCommit = false
                guard wasOurs else { return }
                if landed < -commitDistance {
                    close()
                    onDelete()          // long swipe left commits (delete still confirms)
                } else if landed > commitDistance {
                    close()
                    onRelog()           // long swipe right commits
                } else if landed < -revealWidth * 0.6 {
                    park(at: -revealWidth)   // short swipe + release → buttons stay exposed
                } else if landed > revealWidth * 0.6 {
                    park(at: revealWidth)
                } else {
                    close()
                }
            }
    }

    private func park(at position: CGFloat) {
        withAnimation(Theme.Motion.gesture) { offset = position }
    }

    private func close() {
        withAnimation(Theme.Motion.gesture) { offset = 0 }
        if openRowID == id { openRowID = nil }
    }
}

/// The rows never *looked* tappable — this makes them *feel* tappable: a brief dim+settle
/// on touch teaches "these respond" after one tap, without adding chrome to every card.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
