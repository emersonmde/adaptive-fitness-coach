import WidgetKit
import SwiftUI
import AdaptiveCore

/// Watch Smart Stack + complication widget (build 9): the next scheduled routine on the wrist,
/// tapping deep-links `afcoach://start/<id>` into the watch app, which routes the session
/// container straight into that routine's *adaptive* flow (our engine stays in-session — N2/N3,
/// not a hand-off to Apple's Workout app). Reads the App Group `RoutineStore` off the main
/// actor via the nonisolated helpers.

@main
struct AdaptiveFitnessWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWorkoutComplication()
        QuickLogComplication()
    }
}

// MARK: - Quick-log complication

/// One tap from the watch face into the meal quick-log sheet (`afcoach://quicklog`).
/// Stateless — there's nothing to fetch or refresh; the complication IS the button
/// (always-pending: dictate → parked for the iPhone → done).
struct QuickLogEntry: TimelineEntry {
    var date: Date
}

struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        completion(Timeline(entries: [QuickLogEntry(date: .now)], policy: .never))
    }
}

struct QuickLogComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLogComplication", provider: QuickLogProvider()) { _ in
            QuickLogComplicationView()
                .widgetURL(URL(string: "afcoach://quicklog"))
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Log a Meal")
        .description("Dictate a meal — saved to review on your iPhone.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

private struct QuickLogComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Log a meal", systemImage: "fork.knife")
        case .accessoryCorner:
            Image(systemName: "fork.knife")
                .font(.title2)
                .widgetLabel("Log a meal")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("QUICK LOG", systemImage: "fork.knife").font(.caption2.weight(.semibold))
                Text("Log a meal").font(.headline).lineLimit(1)
                Text("Dictate → iPhone").font(.caption2)
            }
        default: // accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "fork.knife").font(.title3)
            }
            .widgetLabel("Log a meal")
        }
    }
}

struct WatchWorkoutEntry: TimelineEntry {
    var date: Date
    var routineName: String?
    var routineId: String?
    var fires: Date?
    var isStrength: Bool
}

struct WatchWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWorkoutEntry {
        WatchWorkoutEntry(date: .now, routineName: "Morning Run", routineId: nil,
                          fires: .now.addingTimeInterval(3600), isStrength: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchWorkoutEntry) -> Void) {
        completion(entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWorkoutEntry>) -> Void) {
        let e = entry()
        completion(Timeline(entries: [e], policy: .after(e.fires ?? Date().addingTimeInterval(6 * 3600))))
    }
    private func entry() -> WatchWorkoutEntry {
        let routines = RoutineStore.routinesFromDisk()
        guard let next = RoutineStore.nextOccurrence(in: routines) else {
            return WatchWorkoutEntry(date: .now, routineName: nil, routineId: nil, fires: nil, isStrength: false)
        }
        return WatchWorkoutEntry(date: .now, routineName: next.routine.name,
                                 routineId: next.routine.id.uuidString, fires: next.date,
                                 isStrength: next.routine.type == .strength)
    }
}

struct NextWorkoutComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkoutComplication", provider: WatchWorkoutProvider()) { entry in
            ComplicationView(entry: entry)
                .widgetURL(entry.routineId.flatMap { URL(string: "afcoach://start/\($0)") })
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Next Workout")
        .description("Your next routine — tap to start.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
        ])
    }
}

private struct ComplicationView: View {
    let entry: WatchWorkoutEntry
    @Environment(\.widgetFamily) private var family

    private var glyph: String { entry.isStrength ? "dumbbell.fill" : "figure.run" }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let name = entry.routineName {
                Label(name, systemImage: glyph)
            } else {
                Text("No workout scheduled")
            }
        case .accessoryCorner:
            Image(systemName: glyph)
                .font(.title2)
                .widgetLabel(entry.routineName ?? "None")
        case .accessoryRectangular:
            if let name = entry.routineName {
                VStack(alignment: .leading, spacing: 1) {
                    Label("UP NEXT", systemImage: glyph).font(.caption2.weight(.semibold))
                    Text(name).font(.headline).lineLimit(1)
                    if let fires = entry.fires {
                        // A bare time reads as *today* — an occurrence days out needs its day
                        // ("Sat 7:00 AM"), or Tuesday's glance claims a workout this morning.
                        if Calendar.current.isDateInToday(fires) {
                            Text(fires, style: .time).font(.caption2)
                        } else {
                            Text("\(fires, format: .dateTime.weekday(.abbreviated)) \(fires, style: .time)")
                                .font(.caption2)
                        }
                    }
                }
            } else {
                Text("No workout scheduled").font(.caption)
            }
        default: // accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: glyph).font(.title3)
            }
            .widgetLabel(entry.routineName ?? "None")
        }
    }
}
