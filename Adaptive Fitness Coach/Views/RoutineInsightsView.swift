import SwiftUI
import Charts
import AdaptiveCore

/// Per-routine trends (P6.1) — pushed read-only from the routine detail's LAST WORKOUT
/// section (`ProgressionJournalView` is the shape precedent). ONE dominant element: a bar
/// chart of time running per session over the last 28 days — the quantity the adaptive
/// engine actually drives, monotone-meaningful and robust at tiny n. Everything else is a
/// quiet stat line whose "vs 28-day average" suffix appears only once the baseline gate
/// passes (the same gate as the watch summary — Apple-mirroring honesty; never a baseline
/// fabricated from three runs).
///
/// Chart discipline (dataviz method): single series → one hue (the accent), no legend (the
/// title names it); bars thin with rounded data-ends; hairline recessive grid; axis text in
/// secondary ink, never the series color; deltas are facts — no red, no grades.
struct RoutineInsightsView: View {
    let routine: Routine
    let trend: RunTrend

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chartSection
                    statsSection
                }
                .padding(16)
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("insights.screen")
    }

    // MARK: - Hero chart

    @ViewBuilder private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIME RUNNING · LAST 28 DAYS")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            Card {
                if trend.hasChart {
                    chart
                } else {
                    // One session can't be a trend (N6) — say why the chart isn't here.
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar")
                            .font(.title3)
                            .foregroundStyle(Theme.textTertiary)
                        Text("Trends appear as runs accumulate.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("insights.emptyChart")
                }
            }
        }
    }

    private var chart: some View {
        Chart(trend.points, id: \.date) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Minutes running", point.minutesRunning),
                width: .fixed(14)
            )
            .foregroundStyle(Theme.accent)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.textSecondary)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
                    .foregroundStyle(Theme.textSecondary)
                    .font(.caption2)
            }
        }
        .chartYAxisLabel("min", position: .trailing, alignment: .top)
        .frame(height: 170)
        .accessibilityIdentifier("insights.chart")
    }

    // MARK: - Quiet stat lines

    @ViewBuilder private var statsSection: some View {
        if !trend.stats.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST RUN")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                Card(padding: 12, cornerRadius: Theme.radiusInset) {
                    VStack(spacing: 10) {
                        ForEach(trend.stats, id: \.self) { stat in
                            HStack(alignment: .firstTextBaseline) {
                                Text(stat.label)
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(stat.value)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.textPrimary)
                                    if let suffix = stat.baselineSuffix {
                                        Text(suffix)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}
