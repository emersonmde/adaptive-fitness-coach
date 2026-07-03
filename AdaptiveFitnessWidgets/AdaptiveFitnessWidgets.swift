import WidgetKit
import SwiftUI

/// Quick-capture widgets (build 8): two small tiles — Scan and Type — that deep-link straight
/// into the meal-logging flow (`afcoach://log/scan` / `afcoach://log/type`, routed by
/// `MealCaptureRequest`). Static content: the widget IS the button; the day's numbers live in
/// the app and Health, not on the Home Screen (C6 — no ambient calorie pressure).

@main
struct AdaptiveFitnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScanMealWidget()
        TypeMealWidget()
    }
}

// MARK: - Timeline plumbing (static — one entry, never refreshes)

struct StaticEntry: TimelineEntry {
    let date: Date
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

// MARK: - The two tiles

struct ScanMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScanMealWidget", provider: StaticProvider()) { _ in
            LauncherTileView(
                systemImage: "camera.viewfinder",
                title: "Scan a meal",
                url: URL(string: "afcoach://log/scan")!
            )
        }
        .configurationDisplayName("Scan a Meal")
        .description("Opens the camera to scan a receipt, barcode, or label.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct TypeMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TypeMealWidget", provider: StaticProvider()) { _ in
            LauncherTileView(
                systemImage: "keyboard",
                title: "Type a meal",
                url: URL(string: "afcoach://log/type")!
            )
        }
        .configurationDisplayName("Type a Meal")
        .description("Log food by describing it.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Tile view (brand tokens inlined — the widget target doesn't link the app)

private struct LauncherTileView: View {
    let systemImage: String
    let title: String
    let url: URL

    @Environment(\.widgetFamily) private var family

    // Theme.accent / Theme.bg equivalents (the app's design tokens, duplicated by value —
    // a widget extension shouldn't drag the app target in for two colors).
    private let accent = Color(red: 0x34 / 255, green: 0xE2 / 255, blue: 0x7A / 255)
    private let background = Color(red: 0x08 / 255, green: 0x09 / 255, blue: 0x0B / 255)

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: systemImage)
                    .font(.title2)
                    .widgetAccentable()
            default:
                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(url)
    }
}
