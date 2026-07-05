import SwiftUI
import AdaptiveCore

/// One row per routine (the duplication fix): a routine owns its days, shown once as inline
/// badges instead of being repeated under each day section. Matte dark `Card` — glass is
/// reserved for the focal hero, so the list stays a custom canvas, not stock iOS 26.
struct RoutineCard: View {
    let routine: Routine

    private var tint: Color { RoutineTheme.tint(for: routine.type) }

    /// Shown only when a routine has no repeat days yet — a quick hint of what it is.
    private var subtitle: String {
        if routine.hasStrength {
            let n = routine.exerciseItems.count
            return n == 0 ? "Strength" : "\(n) exercise\(n == 1 ? "" : "s")"
        }
        return "HR-driven · builds itself"
    }

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: RoutineTheme.symbol(for: routine.type))
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)   // matches the hero card's clamp discipline
                    if routine.repeatDays.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        DayBadges(days: routine.repeatDays, tint: tint)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
