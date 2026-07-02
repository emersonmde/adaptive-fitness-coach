//
//  Adaptive_Fitness_CoachApp.swift
//  Adaptive Fitness Coach Watch App
//
//  Created by Matthew Emerson on 6/24/26.
//

import SwiftUI
import AdaptiveCore

@main
struct Adaptive_Fitness_Coach_Watch_AppApp: App {
    /// Receive-only routine store (the phone is the source of truth) plus its sync receiver.
    @State private var store: RoutineStore
    @State private var connectivity: WatchConnectivityManager

    init() {
        let store = RoutineStore()
        _store = State(initialValue: store)
        _connectivity = State(initialValue: WatchConnectivityManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            SessionContainerView(store: store,
                                 recordProgressions: connectivity.recordProgressions,
                                 recordRunProgression: connectivity.recordRunProgression)
                .task {
                    // Simulate mode uses a scripted backend and never touches HealthKit, so skip
                    // the authorization prompt (it would otherwise block the scripted run).
                    if !ProcessInfo.processInfo.arguments.contains("-simulateWorkout") {
                        await HealthKitAuthorization.requestAuthorization()
                    }
                    connectivity.activate()
                }
        }
    }
}
