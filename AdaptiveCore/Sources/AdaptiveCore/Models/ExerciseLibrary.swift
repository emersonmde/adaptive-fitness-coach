import Foundation

/// The curated, shared exercise catalog. Lives in the package so the phone (builder) and the
/// watch (session) resolve ids to the same names, archetypes, form demos, and coaching copy —
/// which is why WatchConnectivity only needs to carry the per-routine card list, not the catalog (N4).
///
/// P1 ships a beginner set of dumbbell + bodyweight movements. Every seed weight and rep/hold
/// default is **conservative on purpose** — a seed the user adjusts, not a target to hit (N7).
/// Each entry carries a short `howTo` and a few `tips` for the help screen (watch + iOS info
/// sheet); form demos are SF Symbol placeholders (`FormDemo.symbol`) pending real assets.
public enum ExerciseLibrary {

    public static let all: [Exercise] = [
        Exercise(
            id: "goblet_squat",
            name: "Goblet Squat",
            muscleTags: ["quads", "glutes", "core"],
            archetype: .stationary,
            goodFor: "Building leg strength with a safe, upright squat.",
            howTo: "Hold one dumbbell vertically against your chest. Sit your hips back and down until your thighs are about parallel to the floor, then drive through your heels to stand.",
            tips: ["Keep your chest up and heels planted.", "Push your knees out over your toes — don't let them cave in."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(20)),
            weightStepPounds: 5,
            restSeedSeconds: 120
        ),
        Exercise(
            id: "db_bench_press",
            name: "Dumbbell Bench Press",
            muscleTags: ["chest", "triceps", "shoulders"],
            archetype: .press,
            goodFor: "Pressing strength for chest and arms.",
            howTo: "Lie on a bench with a dumbbell in each hand at chest level. Press both weights straight up until your arms are extended, then lower under control back to your chest.",
            tips: ["Keep your wrists stacked over your elbows.", "Don't bounce the weights — lower for a count of two."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(15)),
            weightStepPounds: 5,
            restSeedSeconds: 120
        ),
        Exercise(
            id: "db_overhead_press",
            name: "Overhead Press",
            muscleTags: ["shoulders", "triceps"],
            archetype: .overheadPress,
            goodFor: "Strong, stable shoulders overhead.",
            howTo: "Stand holding a dumbbell at each shoulder, palms facing forward. Press the weights overhead until your arms are straight, then lower them back to your shoulders.",
            tips: ["Brace your core so you don't arch your lower back.", "Keep the weights moving in a straight line, just in front of your face."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 6...10, seedWeight: .lb(10)),
            weightStepPounds: 5,
            restSeedSeconds: 120
        ),
        Exercise(
            id: "one_arm_row",
            name: "One-Arm Dumbbell Row",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "Back strength and better posture.",
            howTo: "Brace one hand and knee on a bench with your back flat. Let the dumbbell hang in your other hand, then pull it to your ribs, leading with your elbow. Lower under control.",
            tips: ["Pull with your back, not just your arm.", "Keep your torso still — don't twist to lift the weight."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(20)),
            weightStepPounds: 5,
            restSeedSeconds: 120
        ),
        Exercise(
            id: "db_curl",
            name: "Dumbbell Curl",
            muscleTags: ["biceps"],
            archetype: .curl,
            goodFor: "Arm strength with a simple, learnable lift.",
            howTo: "Stand with a dumbbell in each hand, arms at your sides, palms forward. Curl the weights toward your shoulders by bending your elbows, then lower under control.",
            tips: ["Keep your elbows pinned to your sides.", "Don't swing — let the biceps do the work."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 10...15, seedWeight: .lb(12.5)),
            weightStepPounds: 2.5,
            restSeedSeconds: 75
        ),
        Exercise(
            id: "romanian_deadlift",
            name: "Romanian Deadlift",
            muscleTags: ["hamstrings", "glutes", "back"],
            archetype: .stationary,
            goodFor: "Hip-hinge strength for the whole posterior chain.",
            howTo: "Hold a dumbbell in each hand in front of your thighs. With soft knees, push your hips back and lower the weights along your legs until you feel a hamstring stretch, then drive your hips forward to stand.",
            tips: ["Keep the weights close to your legs the whole way.", "Hinge at the hips — your back stays flat, it doesn't round."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(20)),
            weightStepPounds: 5,
            restSeedSeconds: 120
        ),
        Exercise(
            id: "reverse_lunge",
            name: "Reverse Lunge",
            muscleTags: ["quads", "glutes"],
            archetype: .stationary,
            goodFor: "Single-leg strength and balance.",
            howTo: "Stand tall, optionally holding a dumbbell in each hand. Step one foot back and lower until both knees are bent about 90°, then push through your front heel to return to standing. Alternate legs.",
            tips: ["Keep most of your weight on the front foot.", "Lower straight down — don't let the front knee drift past your toes."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(15)),
            weightStepPounds: 5,
            restSeedSeconds: 90
        ),
        Exercise(
            id: "lateral_raise",
            name: "Lateral Raise",
            muscleTags: ["shoulders"],
            archetype: .overheadPress,
            goodFor: "Shoulder width and control with light weight.",
            howTo: "Stand with a light dumbbell in each hand at your sides. With a slight elbow bend, raise both arms out to the sides until they're level with your shoulders, then lower slowly.",
            tips: ["Go light — this is a control exercise, not a heavy one.", "Lead with your elbows, not your hands."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 10...15, seedWeight: .lb(7.5)),
            weightStepPounds: 2.5,
            restSeedSeconds: 75
        ),
        Exercise(
            id: "glute_bridge",
            name: "Glute Bridge",
            muscleTags: ["glutes", "hamstrings"],
            archetype: .stationary,
            goodFor: "Waking up the glutes — bodyweight to start.",
            howTo: "Lie on your back, knees bent, feet flat on the floor. Squeeze your glutes and lift your hips until your body forms a straight line from knees to shoulders, then lower under control.",
            tips: ["Drive through your heels.", "Squeeze your glutes at the top — don't arch your lower back to go higher."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 12...20, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "push_up",
            name: "Push-Up",
            muscleTags: ["chest", "triceps", "core"],
            archetype: .press,
            goodFor: "Upper-body pressing with no equipment.",
            howTo: "Start in a plank with hands a bit wider than your shoulders. Lower your chest toward the floor by bending your elbows, then press back up to a straight-arm plank.",
            tips: ["Keep your body in one straight line — hips don't sag or pike.", "Drop to your knees if needed to keep clean form."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...20, seedWeight: nil),
            restSeedSeconds: 90
        ),
        Exercise(
            id: "plank",
            name: "Plank",
            muscleTags: ["core"],
            archetype: .isometric,
            goodFor: "Core stability held for time.",
            howTo: "Rest on your forearms and toes with your body in a straight line from head to heels. Brace your core and hold, breathing steadily.",
            tips: ["Squeeze your glutes and abs to keep your hips level.", "Don't let your hips sag or rise — stay flat."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .hold(defaultSeconds: 30),
            restSeedSeconds: 60
        ),

        // MARK: - Bodyweight movements (no equipment)

        Exercise(
            id: "sit_up",
            name: "Sit-Up",
            muscleTags: ["core", "hip flexors"],
            archetype: .stationary,
            goodFor: "Building abdominal strength with no equipment.",
            howTo: "Lie on your back, knees bent and feet flat. Cross your arms or reach toward your knees, then curl your torso all the way up to a sitting position. Lower under control.",
            tips: ["Lead with your chest, not your neck.", "Move smoothly — don't yank with your arms."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 15...25, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "bicycle_crunch",
            name: "Bicycle Crunch",
            muscleTags: ["core", "obliques"],
            archetype: .stationary,
            goodFor: "Hitting the abs and obliques together.",
            howTo: "Lie on your back, hands behind your head, knees up. Bring one elbow toward the opposite knee while extending the other leg, then switch sides in a pedaling motion.",
            tips: ["Rotate from your torso, not your arms.", "Keep your lower back pressed into the floor."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 20...30, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "mountain_climber",
            name: "Mountain Climber",
            muscleTags: ["core", "shoulders", "quads"],
            archetype: .stationary,
            goodFor: "Core and conditioning in one fast bodyweight move.",
            howTo: "Start in a straight-arm plank. Drive one knee toward your chest, then quickly switch legs, keeping a steady running rhythm. Count each pair of knees as one rep.",
            tips: ["Keep your hips low and shoulders over your hands.", "Stay light on your feet — speed comes from the hips."],
            formDemo: .symbol("figure.mixed.cardio"),
            defaultSets: 3,
            kind: .reps(repRange: 16...30, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "air_squat",
            name: "Bodyweight Squat",
            muscleTags: ["quads", "glutes"],
            archetype: .stationary,
            goodFor: "Grooving the squat pattern with no load.",
            howTo: "Stand with feet about shoulder-width apart, arms out front for balance. Sit your hips back and down until your thighs are about parallel to the floor, then stand back up.",
            tips: ["Keep your heels down and chest tall.", "Push your knees out in line with your toes."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 15...25, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "superman",
            name: "Superman",
            muscleTags: ["lower back", "glutes"],
            archetype: .stationary,
            goodFor: "Strengthening the lower back and posterior chain.",
            howTo: "Lie face-down with arms extended in front of you. Lift your arms, chest, and legs off the floor at the same time, hold for a beat, then lower under control.",
            tips: ["Lift with your back, not by throwing your head up.", "Keep the movement small and controlled."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 12...20, seedWeight: nil),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "dead_bug",
            name: "Dead Bug",
            muscleTags: ["core"],
            archetype: .stationary,
            goodFor: "Core control that's easy on the lower back.",
            howTo: "Lie on your back with arms reaching up and knees bent at 90°. Slowly lower one arm overhead and the opposite leg toward the floor, then return and switch sides.",
            tips: ["Keep your lower back flat against the floor the whole time.", "Move slowly — control beats speed here."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 12...20, seedWeight: nil),
            restSeedSeconds: 60
        ),
    ]

    /// Look up a catalog entry by id, or `nil` if unknown.
    public static func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }
}
