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
        // UI tests get a fresh, throwaway store each launch for deterministic state.
        let url: URL? = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("uitest-routines-\(UUID().uuidString).json")
            : nil
        _store = State(initialValue: RoutineStore(fileURL: url) { routines in
            connectivity.sync(routines: routines)
        })
    }

    var body: some Scene {
        WindowGroup {
            WeekView(store: store)
                .task {
                    // Push current routines to the watch and (re)register reminders on launch.
                    PhoneConnectivityManager.shared.sync(routines: store.routines)
                    // Skip the system notification prompt under UI test so it can't block the flow.
                    if !uiTesting {
                        await NotificationManager.shared.requestAuthorization()
                        NotificationManager.shared.rescheduleAll(store.routines)
                    }
                }
        }
    }
}
