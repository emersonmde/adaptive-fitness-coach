import SwiftUI
import AdaptiveCore

/// A week-at-a-glance: seven Mon–Sun cells, each showing small semantic dots for the routine
/// types scheduled that day, with today ringed in the brand accent. This is where multi-day
/// routines live — a Mon+Wed routine dots both days without being duplicated as cards.
///
/// `doneDays` (build 11) is the backward glance: days where a workout of ours already exists
/// in Health show a small accent check in the dot row — dot = planned, check = done. Facts
/// only: no counts, no chains, no shame for the unmarked days (binding principle).
struct WeekStrip: View {
    let store: RoutineStore
    var doneDays: Set<DayOfWeek> = []
    var today: DayOfWeek = DayOfWeek(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .monday

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DayOfWeek.localeWeekOrder, id: \.self) { day in
                let types = scheduledTypes(on: day)
                let done = doneDays.contains(day)
                VStack(spacing: 6) {
                    Text(day.letter)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(day == today ? Theme.bg : Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle().fill(day == today ? Theme.accent : Theme.surface2)
                        }
                    // The activity row: a done check supersedes the planned dots (you did
                    // it — the plan is history), otherwise semantic dots for what's scheduled.
                    HStack(spacing: 3) {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(Theme.accent)
                        } else {
                            ForEach(Array(types.enumerated()), id: \.offset) { _, type in
                                Circle().fill(RoutineTheme.tint(for: type)).frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.fullName)\(done ? ", workout done" : types.isEmpty ? ", nothing scheduled" : ", \(types.count) scheduled")")
            }
        }
    }

    /// Distinct routine types scheduled on a given day, in run-before-strength order for stable dots.
    private func scheduledTypes(on day: DayOfWeek) -> [RoutineType] {
        let present = Set(store.routines(on: day).map(\.type))
        return RoutineType.allCases.filter(present.contains)
    }
}
