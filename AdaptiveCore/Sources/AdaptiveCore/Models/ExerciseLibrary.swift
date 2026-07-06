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
            restSeedSeconds: 120,
            equipment: [.dumbbell, .kettlebell]
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
            restSeedSeconds: 120,
            equipment: [.dumbbell, .bench]
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
            restSeedSeconds: 120,
            equipment: [.dumbbell]
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
            restSeedSeconds: 120,
            equipment: [.dumbbell, .bench]
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
            kind: .reps(repRange: 10...15, seedWeight: .lb(10)),
            weightStepPounds: 5,
            restSeedSeconds: 75,
            equipment: [.dumbbell]
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
            restSeedSeconds: 120,
            equipment: [.dumbbell]
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
            restSeedSeconds: 90,
            equipment: [.dumbbell]
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
            kind: .reps(repRange: 10...15, seedWeight: .lb(5)),
            weightStepPounds: 5,
            restSeedSeconds: 75,
            equipment: [.dumbbell]
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
        Exercise(
            id: "split_squat",
            name: "Split Squat",
            muscleTags: ["quads", "glutes"],
            archetype: .stationary,
            goodFor: "Single-leg strength without the balance demand of a lunge.",
            howTo: "Stand in a staggered stance, one foot well in front of the other. Lower straight down until both knees are near 90°, then press through the front heel to stand. Do all reps on one side, then switch.",
            tips: ["Keep your torso tall — don't lean into the front leg.", "The back leg is a kickstand; the front leg does the work."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: nil),
            restSeedSeconds: 90
        ),
        Exercise(
            id: "burpee",
            name: "Burpee",
            muscleTags: ["full body"],
            archetype: .stationary,
            goodFor: "Whole-body conditioning with zero equipment.",
            howTo: "From standing, squat down and place your hands on the floor. Jump your feet back to a plank, do a push-up, jump your feet back in, and stand or jump up. That's one rep.",
            tips: ["Pace yourself — smooth beats fast.", "Step your feet back instead of jumping to make it easier."],
            formDemo: .symbol("figure.mixed.cardio"),
            defaultSets: 3,
            kind: .reps(repRange: 6...15, seedWeight: nil),
            restSeedSeconds: 90
        ),
        Exercise(
            id: "side_plank",
            name: "Side Plank",
            muscleTags: ["core", "obliques"],
            archetype: .isometric,
            goodFor: "Lateral core strength the front plank misses.",
            howTo: "Lie on your side, then prop yourself on your forearm with your feet stacked, lifting your hips so your body forms a straight line. Hold, then repeat on the other side.",
            tips: ["Keep your hips high — don't let them sag toward the floor.", "Stack your shoulder directly over your elbow."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .hold(defaultSeconds: 20),
            restSeedSeconds: 60
        ),
        Exercise(
            id: "calf_raise",
            name: "Calf Raise",
            muscleTags: ["calves"],
            archetype: .stationary,
            goodFor: "Calf strength for running and jumping.",
            howTo: "Stand tall, optionally on a step with your heels hanging off. Rise onto the balls of your feet as high as you can, pause, then lower slowly below level.",
            tips: ["Pause at the top — no bouncing.", "A slow lowering is where the strength is built."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 15...25, seedWeight: nil),
            restSeedSeconds: 60
        ),

        // MARK: - Barbell (P3 library expansion — the coach can program a barbell setup)
        // Seed loads assume a standard 45 lb Olympic bar (deadlift seeded with light plates);
        // steps stay in the ACSM 2009 2–10% band, rests at the long end for heavy compounds
        // (Schoenfeld et al., JSCR 30(7), 2016).

        Exercise(
            id: "barbell_back_squat",
            name: "Barbell Back Squat",
            muscleTags: ["quads", "glutes", "core"],
            archetype: .stationary,
            goodFor: "The classic barbell strength builder for the whole lower body.",
            howTo: "With the bar resting on your upper back and feet shoulder-width, sit your hips back and down until your thighs are about parallel, then drive up through your whole foot.",
            tips: ["Brace your core before every rep.", "Keep the bar over your mid-foot — chest up, knees tracking your toes."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 6...10, seedWeight: .lb(45)),
            weightStepPounds: 5,
            restSeedSeconds: 150,
            equipment: [.barbell]
        ),
        Exercise(
            id: "barbell_bench_press",
            name: "Barbell Bench Press",
            muscleTags: ["chest", "triceps", "shoulders"],
            archetype: .press,
            goodFor: "Heavier pressing than dumbbells allow, with a stable bar path.",
            howTo: "Lie on the bench with your eyes under the bar. Unrack, lower the bar to your mid-chest under control, then press it back up until your arms are straight.",
            tips: ["Keep your feet planted and shoulder blades pinched.", "Use a spotter or safety pins when going heavy."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 6...10, seedWeight: .lb(45)),
            weightStepPounds: 5,
            restSeedSeconds: 150,
            equipment: [.barbell, .bench]
        ),
        Exercise(
            id: "barbell_deadlift",
            name: "Barbell Deadlift",
            muscleTags: ["hamstrings", "glutes", "back"],
            archetype: .stationary,
            goodFor: "Total posterior-chain strength — the biggest pull there is.",
            howTo: "Stand with the bar over your mid-foot. Hinge down, grip the bar just outside your legs, flatten your back, then stand up by driving the floor away. Lower under control.",
            tips: ["The bar stays in contact with your legs the whole lift.", "Set your back flat before you pull — never round to reach the bar."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 5...8, seedWeight: .lb(65)),
            weightStepPounds: 10,
            restSeedSeconds: 180,
            equipment: [.barbell]
        ),
        Exercise(
            id: "barbell_row",
            name: "Barbell Row",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "Back thickness and pulling strength to balance the bench.",
            howTo: "Hinge at the hips until your torso is near parallel, bar hanging at arm's length. Pull the bar to your lower ribs, leading with your elbows, then lower under control.",
            tips: ["Keep your back flat — if it rounds, lighten the bar.", "Pull to your ribs, not your chest."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(45)),
            weightStepPounds: 5,
            restSeedSeconds: 120,
            equipment: [.barbell]
        ),
        Exercise(
            id: "barbell_overhead_press",
            name: "Barbell Overhead Press",
            muscleTags: ["shoulders", "triceps", "core"],
            archetype: .overheadPress,
            goodFor: "Strict overhead strength with both arms driving one bar.",
            howTo: "Stand with the bar at your collarbones, hands just outside your shoulders. Press the bar straight overhead, moving your head back slightly to let it pass, until your arms lock out.",
            tips: ["Squeeze your glutes so your lower back doesn't arch.", "Finish with the bar over your ears, not in front of your face."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 5...8, seedWeight: .lb(45)),
            weightStepPounds: 5,
            restSeedSeconds: 150,
            equipment: [.barbell]
        ),

        // MARK: - Kettlebell

        Exercise(
            id: "kettlebell_swing",
            name: "Kettlebell Swing",
            muscleTags: ["glutes", "hamstrings", "core"],
            archetype: .stationary,
            goodFor: "Explosive hip power and conditioning in one move.",
            howTo: "With the kettlebell just in front of you, hinge and hike it back between your legs, then snap your hips forward to float it to chest height. Let it swing back down and repeat rhythmically.",
            tips: ["It's a hip hinge, not a squat — the arms just hold on.", "Squeeze your glutes hard at the top of every swing."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 12...20, seedWeight: .lb(25)),
            weightStepPounds: 10,
            restSeedSeconds: 90,
            equipment: [.kettlebell]
        ),

        // MARK: - Resistance bands (load isn't measurable in pounds, so bands progress by
        // reps only — seedWeight nil, like bodyweight)

        Exercise(
            id: "band_row",
            name: "Band Row",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "Rowing strength anywhere you can anchor a band.",
            howTo: "Anchor the band at chest height (or loop it around your feet, seated). Pull the handles to your ribs, leading with your elbows and squeezing your shoulder blades, then return slowly.",
            tips: ["Step back until there's tension at full stretch.", "Control the return — don't let the band snap you forward."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 12...20, seedWeight: nil),
            restSeedSeconds: 75,
            equipment: [.band]
        ),
        Exercise(
            id: "band_pull_apart",
            name: "Band Pull-Apart",
            muscleTags: ["shoulders", "upper back"],
            archetype: .row,
            goodFor: "Shoulder health and posture between pressing days.",
            howTo: "Hold the band at shoulder height with straight arms, hands shoulder-width apart. Pull it apart until it touches your chest, squeezing your shoulder blades, then return slowly.",
            tips: ["Keep your arms straight — the shoulder blades do the work.", "Go lighter than you think; this is a control move."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 15...25, seedWeight: nil),
            restSeedSeconds: 60,
            equipment: [.band]
        ),

        // MARK: - Pull-up bar

        Exercise(
            id: "pull_up",
            name: "Pull-Up",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "The benchmark upper-body pull.",
            howTo: "Hang from the bar with an overhand grip a bit wider than your shoulders. Pull until your chin clears the bar, then lower all the way down under control.",
            tips: ["Start each rep from a dead hang — no half reps.", "Can't do one yet? Jump up and lower as slowly as you can."],
            formDemo: .symbol("figure.play"),
            defaultSets: 3,
            kind: .reps(repRange: 3...10, seedWeight: nil),
            restSeedSeconds: 120,
            equipment: [.pullUpBar]
        ),
        Exercise(
            id: "chin_up",
            name: "Chin-Up",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "A pull-up variation that lets the biceps help more.",
            howTo: "Hang from the bar with an underhand grip, hands about shoulder-width. Pull until your chin clears the bar, then lower under control to a full hang.",
            tips: ["Lead with your chest, not your chin.", "Full range beats extra reps."],
            formDemo: .symbol("figure.play"),
            defaultSets: 3,
            kind: .reps(repRange: 3...10, seedWeight: nil),
            restSeedSeconds: 120,
            equipment: [.pullUpBar]
        ),
        Exercise(
            id: "hanging_knee_raise",
            name: "Hanging Knee Raise",
            muscleTags: ["core", "hip flexors"],
            archetype: .stationary,
            goodFor: "Core strength with a grip and shoulder bonus.",
            howTo: "Hang from the bar with straight arms. Without swinging, draw your knees up toward your chest, pause, then lower them slowly back down.",
            tips: ["Curl your pelvis up at the top — don't just lift the legs.", "If you start swinging, pause and reset."],
            formDemo: .symbol("figure.core.training"),
            defaultSets: 3,
            kind: .reps(repRange: 8...15, seedWeight: nil),
            restSeedSeconds: 90,
            equipment: [.pullUpBar]
        ),

        // MARK: - Machines (typical gym stack; 10 lb plates are the common stack increment)

        Exercise(
            id: "lat_pulldown",
            name: "Lat Pulldown",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "Building toward pull-ups with an adjustable load.",
            howTo: "Sit with your thighs under the pads and grip the bar wider than your shoulders. Pull it down to your upper chest, squeezing your shoulder blades, then let it rise under control.",
            tips: ["Lean back only slightly — don't row the weight with momentum.", "Think elbows down and back, not hands."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(50)),
            weightStepPounds: 10,
            restSeedSeconds: 90,
            equipment: [.machine]
        ),
        Exercise(
            id: "seated_cable_row",
            name: "Seated Cable Row",
            muscleTags: ["back", "biceps"],
            archetype: .row,
            goodFor: "A supported horizontal pull that's easy to load.",
            howTo: "Sit with feet on the platform, knees soft, holding the handle at arm's length. Pull it to your stomach, chest tall, then let it return slowly to a full stretch.",
            tips: ["Don't rock — your torso stays nearly still.", "Squeeze your shoulder blades together at the end of each pull."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...12, seedWeight: .lb(50)),
            weightStepPounds: 10,
            restSeedSeconds: 90,
            equipment: [.machine]
        ),
        Exercise(
            id: "leg_press",
            name: "Leg Press",
            muscleTags: ["quads", "glutes"],
            archetype: .stationary,
            goodFor: "Heavy leg work without balancing a bar.",
            howTo: "Sit in the machine with your feet shoulder-width on the platform. Lower the platform until your knees are near 90°, then press back up without locking your knees hard.",
            tips: ["Keep your lower back against the pad the whole time.", "Don't let your knees cave inward as you press."],
            formDemo: .symbol("figure.strengthtraining.functional"),
            defaultSets: 3,
            kind: .reps(repRange: 10...15, seedWeight: .lb(90)),
            weightStepPounds: 10,
            restSeedSeconds: 120,
            equipment: [.machine]
        ),

        // MARK: - Bench (bodyweight + a bench or sturdy surface)

        Exercise(
            id: "bench_dip",
            name: "Bench Dip",
            muscleTags: ["triceps", "chest", "shoulders"],
            archetype: .press,
            goodFor: "Triceps strength using just a bench or sturdy chair.",
            howTo: "Sit on the bench edge, hands beside your hips, then slide off with legs extended. Bend your elbows to lower your hips toward the floor, then press back up.",
            tips: ["Keep your elbows pointing straight back, not flaring out.", "Bend your knees to make it easier; elevate your feet to make it harder."],
            formDemo: .symbol("figure.strengthtraining.traditional"),
            defaultSets: 3,
            kind: .reps(repRange: 8...15, seedWeight: nil),
            restSeedSeconds: 90,
            equipment: [.bench]
        ),
    ]

    /// Look up a catalog entry by id, or `nil` if unknown.
    public static func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }
}
