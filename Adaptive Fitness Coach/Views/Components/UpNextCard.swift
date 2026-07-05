import SwiftUI
import AdaptiveCore

/// The focal "Up Next" hero — the phone's answer to "what do I do next." A subtle `MeshGradient`
/// gives premium depth, a glass time-chip floats over it (neon refracting through), and a single
/// lime glow marks it as the focal element. Read-only: tapping opens the routine (the phone never
/// launches a workout — N4).
struct UpNextCard: View {
    let routine: Routine
    let date: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { RoutineTheme.tint(for: routine.type) }

    /// A run-only routine shows its target minutes; anything with strength shows its exercise
    /// count and rounds (the more meaningful read).
    private var detailText: String {
        if routine.hasStrength {
            let n = routine.exerciseItems.count
            let base = "\(n) exercise\(n == 1 ? "" : "s")"
            return routine.rounds > 1 ? "\(base) · \(routine.rounds) rounds" : base
        }
        return "~\(routine.estimatedMinutes) min"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            meshBackground

            VStack(alignment: .leading, spacing: 0) {
                Text("UP NEXT")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)

                Text(routine.name)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)   // at accessibility sizes wrapping beats shrink-then-truncate
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    StateDot(color: tint, label: routine.type.displayName)
                    Text(detailText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 8)

                Text(RelativeWhen.string(for: date))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 14)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusHero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusHero, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
        )
        // Kept subtle: at higher opacity/radius the halo reads as a gradient wash, not a glow.
        .shadow(color: Theme.accent.opacity(reduceMotion ? 0 : 0.10), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// A near-black mesh with faint lime/run-green pooled in two corners — depth, not decoration.
    private var meshBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                Theme.bg, Theme.surface1, Theme.bg,
                Color(hex: 0x0C1611), Theme.surface1, Color(hex: 0x14180A),
                Theme.bg, Theme.bg, Theme.surface1,
            ]
        )
    }
}

/// Friendly relative phrasing for a future date: "Today · 7:00 AM", "Tomorrow · 7:00 AM",
/// "Wed · 7:00 AM", else "Jun 30 · 7:00 AM".
enum RelativeWhen {
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(time)" }
        let startNow = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startNow, to: startDate).day ?? 0
        if (0..<7).contains(days) {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
        }
        return "\(date.formatted(.dateTime.month().day())) · \(time)"
    }
}
