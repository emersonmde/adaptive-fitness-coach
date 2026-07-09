import SwiftUI
import AdaptiveCore

/// The day's budget — ONE ring, one variable (the watch's ring discipline, on the phone).
///
/// Under target: emerald fill of `DayBudget.fillFraction`, consumed count as the hero.
/// At/over: the ring is full and STAYS full (never a second lap — the rejected dual-arc
/// precedent), the tint shifts once to heat-amber (the app's gradient-job color, never red —
/// red is danger only), and the sub-line becomes plain arithmetic ("230 over"). No pulse, no
/// alarm: a budget informs, it never demands attention (amended C6).
struct CalorieGaugeView: View {
    let budget: DayBudget

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface2, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            Circle()
                .trim(from: 0, to: budget.fillFraction)
                .stroke(
                    budget.isOver ? Theme.heat : Theme.accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Theme.Motion.gentle, value: budget.fillFraction)
                .animation(nil, value: budget.isOver)   // the tint shift is a state, not a show

            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "fork.knife")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(Int(budget.consumedKcal.rounded()).formatted())")
                        .font(Theme.metricNumber)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("meal.day.gauge.consumed")
                }
                // Always the budget denominator — the ring's meaning (eaten of budget). Over-ness
                // is carried by the ring's amber tint and the "N over" remaining line below, so
                // the center never flips label.
                Text("of \(budget.targetKcal.formatted())")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("meal.day.gauge.target")
            }
        }
        .frame(width: 168, height: 168)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if let over = budget.overKcal {
            "\(Int(budget.consumedKcal)) calories eaten, \(over) over your \(budget.targetKcal) target"
        } else {
            "\(Int(budget.consumedKcal)) of \(budget.targetKcal) calories, \(budget.remainingKcal ?? 0) left"
        }
    }
}
