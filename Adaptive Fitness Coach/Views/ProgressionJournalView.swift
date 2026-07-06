import SwiftUI
import AdaptiveCore

/// The P6 progression journal: every seed change, newest first, with its why — the app's
/// adaptation made legible after the fact ("Fri · Bicep Curl 12 → 13 reps — clean session").
/// Read-only; the confirm cards on the hub are where decisions happen.
struct ProgressionJournalView: View {
    let journal: ProgressionJournal

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if journal.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedByDay, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(dayLabel(group.day))
                                    .font(.caption.weight(.semibold))
                                    .tracking(1.5)
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.horizontal, 4)
                                ForEach(group.entries) { entry in
                                    JournalRow(entry: entry)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("journal.screen")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 38))
                .foregroundStyle(Theme.textTertiary)
            Text("No changes yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Finish a workout and every seed change lands here, with its reason.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var groupedByDay: [(day: Date, entries: [ProgressionJournalEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: journal.entries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        let sameWeek = calendar.dateComponents([.day], from: day, to: Date()).day.map { $0 < 7 } ?? false
        let format: Date.FormatStyle = sameWeek
            ? .dateTime.weekday(.wide)
            : .dateTime.month(.abbreviated).day()
        return day.formatted(format).uppercased()
    }
}

private struct JournalRow: View {
    let entry: ProgressionJournalEntry

    var body: some View {
        Card(padding: 12, cornerRadius: Theme.radiusInset) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    if let badge = kindBadge {
                        Text(badge.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge.color)
                    }
                }
                Text(entry.changeText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text(detailLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Micro-steps are the normal case and get no badge (quiet default); the two decided
    /// outcomes are labeled.
    private var kindBadge: (text: String, color: Color)? {
        switch entry.kind {
        case .micro: return nil
        case .confirmed: return ("CONFIRMED", Theme.accent)
        case .declined: return ("HELD", Theme.textTertiary)
        }
    }

    private var detailLine: String {
        var parts: [String] = [entry.routineName]
        if let reason = entry.reason { parts.append(reason) }
        if let effort = entry.perceivedEffort {
            // Coarse vocabulary (P6.1) — historical fine-grained ratings bucket to it too.
            parts.append("felt \(EffortLevel(score: effort)?.label.lowercased() ?? "\(effort)")")
        }
        return parts.joined(separator: " · ")
    }
}
