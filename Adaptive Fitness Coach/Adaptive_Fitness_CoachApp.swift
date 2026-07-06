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
    /// P6: the progression journal (every seed change with its why) and the pending
    /// structural-confirm proposals, both fed by inbound watch batches.
    @State private var journal: ProgressionJournal
    @State private var proposals: ProgressionProposalStore

    init() {
        // Activate the watch link first so the store's onChange has somewhere to send.
        PhoneConnectivityManager.shared.activate()
        let connectivity = PhoneConnectivityManager.shared
        // UI tests / demo seeding get a fresh, throwaway store each launch (deterministic, never
        // touches the real routines file).
        let ephemeral = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            || ProcessInfo.processInfo.arguments.contains("-seedDemo")
        func ephemeralURL(_ name: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-\(name)-\(UUID().uuidString).json")
        }
        let url: URL? = ephemeral ? ephemeralURL("routines") : nil
        let store = RoutineStore(fileURL: url) { routines in
            connectivity.sync(routines: routines)
        }
        let journal = ProgressionJournal(fileURL: ephemeral ? ephemeralURL("journal") : nil)
        let proposals = ProgressionProposalStore(fileURL: ephemeral ? ephemeralURL("proposals") : nil)
        // Let inbound progressions (a weight/rep bump recorded on the watch) apply to the store,
        // journaled and proposal-gated (P6).
        connectivity.store = store
        connectivity.journal = journal
        connectivity.proposals = proposals
        // UI tests: seed a structural proposal + journal history through the real intake path.
        if ProcessInfo.processInfo.arguments.contains("-seedProposal") {
            Self.seedProposalDemo(store: store, journal: journal, proposals: proposals)
        }
        // Dev/QA only: populate a throwaway store with demo routines for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-seedDemo"), store.routines.isEmpty {
            store.add(Routine(name: "Morning Run",
                              repeatDays: [.tuesday, .friday], scheduleTime: ScheduleTime(hour: 7, minute: 0),
                              reminderEnabled: true,
                              cards: [.run(RunCard())]))
            let circuit: [WorkoutCard] = ["goblet_squat", "db_bench_press", "one_arm_row", "plank"]
                .compactMap { ExerciseLibrary.exercise(id: $0) }
                .flatMap { [WorkoutCard.exercise(StrengthExerciseItem(from: $0)), .rest(RestCard(seconds: 30))] }
            store.add(Routine(name: "Strength Circuit",
                              repeatDays: [.monday, .wednesday], scheduleTime: ScheduleTime(hour: 18, minute: 30),
                              cards: circuit, rounds: 3))
        }
        _store = State(initialValue: store)
        _journal = State(initialValue: journal)
        _proposals = State(initialValue: proposals)
    }

    /// `-seedProposal` (UI tests): a strength routine whose squat topped its band, arriving
    /// as a real v4 batch — micro rep bump journaled + a structural load-step proposal pending.
    @MainActor
    private static func seedProposalDemo(
        store: RoutineStore, journal: ProgressionJournal, proposals: ProgressionProposalStore
    ) {
        let squat = StrengthExerciseItem(exerciseId: "goblet_squat", reps: 12, seedWeight: .lb(20))
        let curl = StrengthExerciseItem(exerciseId: "db_curl", reps: 12, seedWeight: .lb(15))
        let routine = Routine(name: "Strength Circuit", repeatDays: [.monday],
                              cards: [.exercise(squat), .rest(RestCard(seconds: 60)), .exercise(curl)],
                              rounds: 3)
        store.add(routine)
        ProgressionIntake.receive(
            ProgressionBatch(
                routineId: routine.id,
                updates: [ProgressionUpdate(exerciseId: "db_curl", reps: 13, reason: "clean session")],
                proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8,
                                              reason: "topped the rep band")],
                perceivedEffort: 6,
                sessionDate: Date()
            ),
            store: store, journal: journal, proposals: proposals
        )
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-lookupLab") {
                // P4 spike/regression harness (CQ1/CQ3): per-rung lookup coverage on device.
                LookupLabView()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        WeekView(store: store, journal: journal, proposals: proposals)
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
