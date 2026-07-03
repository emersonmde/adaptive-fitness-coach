import AppIntents
import Foundation
import AdaptiveCore

/// A routine modeled as an App Entity (build 9, partial P5) so Siri/Shortcuts/Spotlight can
/// reference it by name — "start my Morning Run", "when's my Push Day". Reads the App Group
/// `RoutineStore`, so it resolves without the app running.
struct RoutineEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static let defaultQuery = RoutineEntityQuery()

    var id: String   // the routine's UUID string
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(routine: Routine) {
        self.init(id: routine.id.uuidString, name: routine.name)
    }
}

struct RoutineEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        RoutineStore(onChange: { _ in }).routines
            .filter { identifiers.contains($0.id.uuidString) }
            .map(RoutineEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RoutineEntity] {
        RoutineStore(onChange: { _ in }).routines.map(RoutineEntity.init)
    }
}

extension RoutineEntityQuery: EnumerableEntityQuery {
    @MainActor
    func allEntities() async throws -> [RoutineEntity] {
        RoutineStore(onChange: { _ in }).routines.map(RoutineEntity.init)
    }
}

/// "Start my Morning Run" from the phone. Workouts run on the watch (our adaptive engine —
/// N2/N3), so the phone intent opens the app and points the user to their wrist rather than
/// starting a non-adaptive workout here. The watch's own `StartRoutineIntent` does the real
/// in-session start.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let description = IntentDescription("Start one of your routines (on Apple Watch).")
    static let openAppWhenRun = true

    @Parameter(title: "Routine")
    var routine: RoutineEntity

    init() {}
    init(routine: RoutineEntity) { self.routine = routine }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Open Adaptive Fitness Coach on your Apple Watch to start \(routine.name).")
    }
}
