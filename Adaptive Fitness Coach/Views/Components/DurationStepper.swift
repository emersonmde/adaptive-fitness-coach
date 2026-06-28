import SwiftUI

/// A compact, dark/neon stepper for a routine's target duration. Numbers use SF Rounded tabular
/// digits (the app's convention for anything numeric); the ± buttons disable at the bounds.
struct DurationStepper: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 10...90
    var step: Int = 5

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(minutes)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text("min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                stepButton("minus", enabled: minutes > range.lowerBound) {
                    minutes = max(range.lowerBound, minutes - step)
                }
                stepButton("plus", enabled: minutes < range.upperBound) {
                    minutes = min(range.upperBound, minutes + step)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duration")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(range.upperBound, minutes + step)
            case .decrement: minutes = max(range.lowerBound, minutes - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 40, height: 40)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
