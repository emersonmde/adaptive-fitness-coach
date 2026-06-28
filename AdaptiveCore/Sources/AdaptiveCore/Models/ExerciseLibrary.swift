import Foundation

/// The curated, shared exercise catalog. Lives in the package so the phone (builder) and the
/// watch (session) resolve ids to the same names, archetypes, and form demos — which is why
/// WatchConnectivity only needs to carry the per-routine card list, not the catalog (N4).
///
/// P1 ships a small beginner set of dumbbell + bodyweight movements. Every seed weight and
/// rep/hold default is **conservative on purpose** — a seed the user adjusts, not a target to
/// hit (N7). Form demos are SF Symbol placeholders (`FormDemo.symbol`) pending real assets.
public enum ExerciseLibrary {

    public static let all: [Exercise] = [
        Exercise(
            id: "goblet_squat",
            name: "Goblet Squat",
            muscleTags: ["quads", "glutes", "core"],
            archetype: .stationary,
            goodFor: "Building leg strength with a safe, upright squat.",
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 10, seedWeight: .lb(20))
        ),
        Exercise(
            id: "db_bench_press",
            name: "Dumbbell Bench Press",
            muscleTags: ["chest", "triceps", "shoulders"],
            archetype: .press,
            goodFor: "Pressing strength for chest and arms.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 10, seedWeight: .lb(15))
        ),
        Exercise(
            id: "db_overhead_press",
            name: "Overhead Press",
            muscleTags: ["shoulders", "triceps"],
            archetype: .overheadPress,
            goodFor: "Strong, stable shoulders overhead.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 8, seedWeight: .lb(10))
        ),
        Exercise(
            id: "one_arm_row",
            name: "One-Arm Dumbbell Row",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "Back strength and better posture.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 10, seedWeight: .lb(20))
        ),
        Exercise(
            id: "db_curl",
            name: "Dumbbell Curl",
            muscleTags: ["biceps"],
            archetype: .curl,
            goodFor: "Arm strength with a simple, learnable lift.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 12, seedWeight: .lb(12.5))
        ),
        Exercise(
            id: "romanian_deadlift",
            name: "Romanian Deadlift",
            muscleTags: ["hamstrings", "glutes", "back"],
            archetype: .stationary,
            goodFor: "Hip-hinge strength for the whole posterior chain.",
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 10, seedWeight: .lb(20))
        ),
        Exercise(
            id: "reverse_lunge",
            name: "Reverse Lunge",
            muscleTags: ["quads", "glutes"],
            archetype: .stationary,
            goodFor: "Single-leg strength and balance.",
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 10, seedWeight: .lb(15))
        ),
        Exercise(
            id: "lateral_raise",
            name: "Lateral Raise",
            muscleTags: ["shoulders"],
            archetype: .overheadPress,
            goodFor: "Shoulder width and control with light weight.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 12, seedWeight: .lb(7.5))
        ),
        Exercise(
            id: "glute_bridge",
            name: "Glute Bridge",
            muscleTags: ["glutes", "hamstrings"],
            archetype: .stationary,
            goodFor: "Waking up the glutes — bodyweight to start.",
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(defaultReps: 12, seedWeight: nil)
        ),
        Exercise(
            id: "push_up",
            name: "Push-Up",
            muscleTags: ["chest", "triceps", "core"],
            archetype: .press,
            goodFor: "Upper-body pressing with no equipment.",
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(defaultReps: 8, seedWeight: nil)
        ),
        Exercise(
            id: "plank",
            name: "Plank",
            muscleTags: ["core"],
            archetype: .isometric,
            goodFor: "Core stability held for time.",
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .hold(defaultSeconds: 30)
        ),
    ]

    /// Look up a catalog entry by id, or `nil` if unknown.
    public static func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }
}
