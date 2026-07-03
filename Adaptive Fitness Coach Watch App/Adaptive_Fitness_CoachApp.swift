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
                .onOpenURL { url in
                    // Complication / Smart Stack deep link: afcoach://start/<routineId> →
                    // route the session container straight into that routine (build 9).
                    guard url.scheme == "afcoach", url.host == "start" else { return }
                    let id = url.lastPathComponent
                    if !id.isEmpty { WorkoutLaunchRequest.shared.request(routineId: id) }
                }
                .task {
                    // Simulate modes use scripted backends and never touch HealthKit, so skip
                    // the authorization prompt for ALL of them (it would otherwise block the
                    // scripted flows — simctl can't grant HealthKit auth).
                    let args = ProcessInfo.processInfo.arguments
                    let simulated = args.contains { $0.hasPrefix("-simulate") }
                    if !simulated {
                        await HealthKitAuthorization.requestAuthorization()
                    }
                    connectivity.activate()
                }
        }
    }
}
