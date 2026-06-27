import SwiftUI
import AdaptiveCore

/// Compact inline day pills (MON · WED) for a routine's single row — the heart of the
/// "one row per routine" fix: a routine shows all its days at once instead of being
/// duplicated across day sections.
struct DayBadges: View {
    let days: Set<DayOfWeek>
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DayOfWeek.weekOrder.filter(days.contains), id: \.self) { day in
                Text(day.shortName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
    }
}

/// A semantic state marker that always pairs a colored dot with a label — never hue alone, so
/// it reads for color-blind users and reinforces the watch's color language.
struct StateDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
