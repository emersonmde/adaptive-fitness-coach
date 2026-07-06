//
//  Adaptive_Fitness_CoachApp.swift
//  Adaptive Fitness Coach Watch App
//
//  Created by Matthew Emerson on 6/24/26.
//

import SwiftUI
import WatchKit
import AdaptiveCore

/// The OS relaunches the app through this hook when it holds a workout session the app should
/// recover (crash/jetsam mid-workout). We recover-and-finalize — the engine state died with the
/// process, so the honest move is to land the collected samples in Health and return to idle
/// (see `WorkoutRecoveryService`).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        // Scripted/simulated runs never own a real HKWorkoutSession — leave them untouched.
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-simulate") }) else { return }
        Task { @MainActor in
            await WorkoutRecoveryService.recoverAndFinalizeAbandonedSession()
        }
    }
}

@main
struct Adaptive_Fitness_Coach_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
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
                                 connectivity: connectivity,
                                 recordProgression: connectivity.record)
                .onOpenURL { url in
                    // Complication / Smart Stack deep link: afcoach://start/<routineId> →
                    // route the session container straight into that routine (build 9).
                    guard url.scheme == "afcoach", url.host == "start" else { return }
                    let id = url.lastPathComponent
                    if !id.isEmpty { WorkoutLaunchRequest.shared.request(routineId: id) }
                }
                .task {
                    // Activate WatchConnectivity FIRST, independent of the HealthKit-auth await
                    // below: activation is what lets queued progression transfers (and the
                    // phone's routine context) flow, and sequencing it behind a modal
                    // authorization prompt would stall sync until the user answered.
                    connectivity.activate()

                    // Simulate modes use scripted backends and never touch HealthKit, so skip
                    // the authorization prompt for ALL of them (it would otherwise block the
                    // scripted flows — simctl can't grant HealthKit auth).
                    let args = ProcessInfo.processInfo.arguments
                    let simulated = args.contains { $0.hasPrefix("-simulate") }
                    if !simulated {
                        await HealthKitAuthorization.requestAuthorization()
                        // A crash mid-workout leaves an orphaned HKWorkoutSession in the OS.
                        // Recover-and-finalize it so the data lands in Health and the next
                        // Start isn't blocked (no-op when there's nothing to recover).
                        await WorkoutRecoveryService.recoverAndFinalizeAbandonedSession()
                    }
                }
        }
    }
}
