import SwiftUI

/// The app's quantity control — a stock `Stepper` was the one visibly off-theme control
/// (light UIKit capsule on the dark cards) with sub-44pt targets. Same shape everywhere a
/// serving count is set: confirmation rows and the edit sheet. The "×N" label is always
/// present so a first-time user knows what the buttons step (an unlabeled stepper next to
/// a food name reads as mystery chrome).
struct QuantityStepper: View {
    @Binding var quantity: Int
    var range: ClosedRange<Int> = 1...20
    /// Callers whose row already states the count (the edit sheet's "2 × 140 = 280 kcal"
    /// line) hide the ×N so the same number isn't said twice in one row.
    var showsCount: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showsCount {
                Text("×\(quantity)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(quantity > 1 ? Theme.textPrimary : Theme.textSecondary)
                    .frame(minWidth: 26, alignment: .trailing)
            }
            stepButton(systemImage: "minus", enabled: quantity > range.lowerBound) {
                quantity = max(range.lowerBound, quantity - 1)
            }
            stepButton(systemImage: "plus", enabled: quantity < range.upperBound) {
                quantity = min(range.upperBound, quantity + 1)
            }
        }
        // One adjustable element, the way VoiceOver expects a stepper to read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quantity")
        .accessibilityValue("\(quantity)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if quantity < range.upperBound { quantity += 1 }
            case .decrement: if quantity > range.lowerBound { quantity -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Theme.Haptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
                // The glyph circle stays compact; the touch target doesn't.
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
