import SwiftUI
import AdaptiveCore

/// A week-at-a-glance: seven Mon–Sun cells, each showing small semantic dots for the routine
/// types scheduled that day, with today ringed in the brand accent. This is where multi-day
/// routines live — a Mon+Wed routine dots both days without being duplicated as cards.
struct WeekStrip: View {
    let store: RoutineStore
    var today: DayOfWeek = DayOfWeek(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .monday

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DayOfWeek.localeWeekOrder, id: \.self) { day in
                let types = scheduledTypes(on: day)
                VStack(spacing: 6) {
                    Text(day.letter)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(day == today ? Theme.bg : Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle().fill(day == today ? Theme.accent : Theme.surface2)
                        }
                    // Dots for the types scheduled that day (semantic colors).
                    HStack(spacing: 3) {
                        ForEach(Array(types.enumerated()), id: \.offset) { _, type in
                            Circle().fill(RoutineTheme.tint(for: type)).frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.fullName)\(types.isEmpty ? ", nothing scheduled" : ", \(types.count) scheduled")")
            }
        }
    }

    /// Distinct routine types scheduled on a given day, in run-before-strength order for stable dots.
    private func scheduledTypes(on day: DayOfWeek) -> [RoutineType] {
        let present = Set(store.routines(on: day).map(\.type))
        return RoutineType.allCases.filter(present.contains)
    }
}
