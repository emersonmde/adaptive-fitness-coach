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
                              repeatDays: [.monday, .wednesday], scheduleTime: ScheduleTime(hour: 18, minute: 30),
                              exercises: ["goblet_squat", "db_bench_press", "one_arm_row", "plank"]
                                .compactMap { ExerciseLibrary.exercise(id: $0) }
                                .map { StrengthExerciseItem(from: $0) }))
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            WeekView(store: store)
                .preferredColorScheme(.dark) // dark/neon brand: force dark regardless of system
                .tint(Theme.accent)
                .task {
                    // Push current routines to the watch on launch.
                    PhoneConnectivityManager.shared.sync(routines: store.routines)
                    // Re-sync calendar events for any scheduled routines. Never prompts: it only
                    // touches events if full access was already granted (so UI tests stay clean).
                    await CalendarService.shared.syncAll(store.routines)
                }
        }
    }
}
