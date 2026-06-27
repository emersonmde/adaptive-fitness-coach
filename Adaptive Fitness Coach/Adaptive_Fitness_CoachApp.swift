//
//  Adaptive_Fitness_CoachApp.swift
//  Adaptive Fitness Coach
//
//  Created by Matthew Emerson on 6/24/26.
//

import SwiftUI
import AdaptiveCore

@main
struct Adaptive_Fitness_CoachApp: App {
    /// The single routine store, wired so every local change pushes to the watch.
    @State private var store: RoutineStore

    private let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        // Activate the watch link first so the store's onChange has somewhere to send.
        PhoneConnectivityManager.shared.activate()
        let connectivity = PhoneConnectivityManager.shared
        // UI tests / demo seeding get a fresh, throwaway store each launch (deterministic, never
        // touches the real routines file).
        let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            || ProcessInfo.processInfo.arguments.contains("-seedDemo")
        let url: URL? = ephemeral
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ephemeral-routines-\(UUID().uuidString).json")
            : nil
        let store = RoutineStore(fileURL: url) { routines in
            connectivity.sync(routines: routines)
        }
        // Dev/QA only: populate a throwaway store with demo routines for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-seedDemo"), store.routines.isEmpty {
            store.add(Routine(name: "Morning Run", type: .adaptiveRun,
                              repeatDays: [.tuesday, .friday], scheduleTime: ScheduleTime(hour: 7, minute: 0),
                              reminderEnabled: true))
            store.add(Routine(name: "Strength Circuit", type: .strength,
                              repeatDays: [.monday, .wednesday], scheduleTime: ScheduleTime(hour: 18, minute: 30)))
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            WeekView(store: store)
                .preferredColorScheme(.dark) // dark/neon brand: force dark regardless of system
                .tint(Theme.accent)
                .task {
                    // Push current routines to the watch and (re)register reminders on launch.
                    PhoneConnectivityManager.shared.sync(routines: store.routines)
                    // Install the notification delegate + category so reminders present in the
                    // foreground and taps route. (Harmless under UI test; only the prompt is skipped.)
                    NotificationManager.shared.configure()
                    // Skip the system notification prompt under UI test / demo so it can't block the UI.
                    if !uiTesting && !ProcessInfo.processInfo.arguments.contains("-seedDemo") {
                        await NotificationManager.shared.requestAuthorization()
                        NotificationManager.shared.rescheduleAll(store.routines)
                    }
                }
        }
    }
}
