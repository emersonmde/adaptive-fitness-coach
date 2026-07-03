import WidgetKit
import SwiftUI
import AdaptiveCore

/// "Next workout" widget (build 9): reads the App Group `RoutineStore` and shows the next
/// scheduled routine + when it fires, deep-linking into the app. Home Screen (systemSmall)
/// and Lock Screen (accessory) families. Refreshes at the occurrence time.
struct NextWorkoutEntry: TimelineEntry {
    var date: Date
    var routineName: String?
    var routineId: String?
    var fires: Date?
    var isStrength: Bool
}

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: .now, routineName: "Morning Run", routineId: nil,
                         fires: .now.addingTimeInterval(3600), isStrength: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextWorkoutEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh at the occurrence (so it rolls to the following one), else in ~6h.
        let refresh = entry.fires ?? Date().addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> NextWorkoutEntry {
        let routines = RoutineStore.routinesFromDisk()
        guard let next = RoutineStore.nextOccurrence(in: routines) else {
            return NextWorkoutEntry(date: .now, routineName: nil, routineId: nil, fires: nil, isStrength: false)
        }
        return NextWorkoutEntry(
            date: .now,
            routineName: next.routine.name,
            routineId: next.routine.id.uuidString,
            fires: next.date,
            isStrength: next.routine.type == .strength
        )
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkoutWidget", provider: NextWorkoutProvider()) { entry in
            NextWorkoutView(entry: entry)
                .widgetURL(entry.routineId.flatMap { URL(string: "afcoach://start/\($0)") })
        }
        .configurationDisplayName("Next Workout")
        .description("Your next scheduled routine and when it starts.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

private struct NextWorkoutView: View {
    let entry: NextWorkoutEntry
    @Environment(\.widgetFamily) private var family

    // Brand-neutral watch/phone semantics inlined (the extension avoids the app's Theme).
    private let run = Color(red: 0x34 / 255, green: 0xE2 / 255, blue: 0x7A / 255)
    private let strength = Color(red: 0x4C / 255, green: 0x8D / 255, blue: 0xFF / 255)
    private let background = Color(red: 0x08 / 255, green: 0x09 / 255, blue: 0x0B / 255)

    private var tint: Color { entry.isStrength ? strength : run }
    private var glyph: String { entry.isStrength ? "dumbbell.fill" : "figure.run" }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: glyph).font(.title3).widgetAccentable()
            case .accessoryRectangular:
                rectangular
            default:
                small
            }
        }
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var small: some View {
        if let name = entry.routineName {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: glyph).font(.title2).foregroundStyle(tint)
                Text("UP NEXT").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                Text(name).font(.headline).foregroundStyle(.white).lineLimit(2)
                if let fires = entry.fires {
                    Text(fires, format: relativeDayTime(fires))
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let name = entry.routineName {
            VStack(alignment: .leading, spacing: 2) {
                Label("UP NEXT", systemImage: glyph).font(.caption2.weight(.semibold)).widgetAccentable()
                Text(name).font(.headline).lineLimit(1)
                if let fires = entry.fires {
                    Text(fires, format: relativeDayTime(fires)).font(.caption2)
                }
            }
        } else {
            Text("No workout scheduled").font(.caption)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(.white.opacity(0.5))
            Text("No workout scheduled").font(.caption).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same-week days read as the weekday; today/tomorrow are named; then the time.
    private func relativeDayTime(_ date: Date) -> Date.FormatStyle {
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInTomorrow(date) {
            return .dateTime.hour().minute()
        }
        return .dateTime.weekday(.abbreviated).hour().minute()
    }
}
