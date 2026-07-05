import SwiftUI
import AdaptiveCore

/// The watch launch picker: flip through ALL your routines with the Digital Crown (vertical paging)
/// and start any one — not just "up next". Fixes "I'm late" or "it's raining, swap the run for an
/// indoor strength session" without editing the schedule. It opens on the next scheduled routine;
/// routing by the picked routine's type happens above this view (a strength pick starts the
/// strength flow, a run pick the run flow, a mixed pick the sequence).
struct RoutineLaunchPicker: View {
    let routines: [Routine]
    /// Page to open on — the "up next" routine.
    let initialIndex: Int
    let onStart: (Routine) -> Void

    @State private var selection: Int

    init(routines: [Routine], initialIndex: Int, onStart: @escaping (Routine) -> Void) {
        self.routines = routines
        self.initialIndex = initialIndex
        self.onStart = onStart
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                RoutineLaunchCard(
                    routine: routine,
                    position: (index + 1, routines.count),
                    isUpNext: index == initialIndex,
                    onStart: { onStart(routine) }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.verticalPage)   // Digital-Crown / swipe paging through routines
    }
}

/// One routine page: its identity (kind icon + name + summary), where it sits in the list, and a
/// single Start. The accent follows the routine's kind (green run / blue strength), matching the
/// flow it launches.
private struct RoutineLaunchCard: View {
    let routine: Routine
    let position: (current: Int, total: Int)
    let isUpNext: Bool
    let onStart: () -> Void

    var body: some View {
        let kind = RoutineKind(routine)
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: kind.icon)
                .font(.title3)
                .foregroundStyle(kind.tint)
            VStack(spacing: 3) {
                Text(isUpNext ? "UP NEXT" : "\(position.current) OF \(position.total)")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textSecondary)
                Text(routine.name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onStart) {
                Text("Start")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
            }
            .tint(kind.tint)
            if position.total > 1 {
                Text("Turn the crown for more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .pagedWorkoutBackground(kind.field)
    }
}

/// The launch-time display category for a routine: the icon, accent, field tint, and one-line
/// summary shown on its picker card — derived from its cards (mirrors how the flow is routed).
private struct RoutineKind {
    let icon: String
    let tint: Color
    let field: Color
    let summary: String

    init(_ routine: Routine) {
        let blocks = routine.expandedCards.workoutBlocks()
        if blocks.count > 1 {
            icon = "figure.mixed.cardio"
            tint = WatchTheme.run
            field = WatchTheme.runField
            summary = "Run + strength · \(blocks.count) parts"
        } else if routine.type == .strength {
            let n = routine.exerciseItems.count
            icon = "dumbbell.fill"
            tint = WatchTheme.strength
            field = WatchTheme.strengthField
            summary = "Strength · \(n) exercise\(n == 1 ? "" : "s")"
        } else {
            let mins = routine.firstRunCard?.totalMinutes ?? routine.estimatedMinutes
            icon = "figure.run"
            tint = WatchTheme.run
            field = WatchTheme.runField
            summary = "Run / Walk · ~\(mins) min"
        }
    }
}
