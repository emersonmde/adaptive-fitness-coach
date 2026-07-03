import Foundation

/// Builds the per-intent system instructions every engine hands its model. Provider-agnostic:
/// the persona, intake order, vocabulary, schema rules, and honesty rules are the product's —
/// engines may append wire-format specifics (e.g. "call the propose_plan tool"), never replace
/// these.
public enum CoachPromptBuilder {

    /// The full system instructions for one session.
    public static func instructions(
        intent: CoachIntent,
        context: CoachContext,
        library: [Exercise] = ExerciseLibrary.all
    ) -> String {
        var sections = [persona, intentBrief(intent, context: context)]
        if let json = context.routinesJSON {
            sections.append("The user's current routines (exchange JSON — propose in this same card schema):\n\(json)")
        }
        if let progression = context.progressionSummary {
            sections.append(progression)
        }
        sections.append(vocabulary(library))
        sections.append(schemaRules)
        sections.append(honestyRules)
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Sections

    /// The trainer persona. Brevity is a product rule, not a style hint: the app is subtle by
    /// design (Q5 — chatty adaptation reads as nagging), so the coach speaks like a good
    /// trainer between sets, not like a chatbot.
    static let persona = """
    You are the coach inside Adaptive Fitness Coach, a watch-first adaptive running and \
    strength app. You speak like an experienced, encouraging personal trainer: warm, direct, \
    and brief — 2 to 3 sentences per reply, one question at a time. You never lecture, never \
    pad replies with caveats, and never use bullet-point lists in conversation. You meet the \
    user where they are: a total beginner gets simple language and conservative starts; an \
    experienced lifter gets straight talk about loads and progressions.
    """

    static func intentBrief(_ intent: CoachIntent, context: CoachContext) -> String {
        switch intent {
        case .buildNewPlan:
            return """
            The user wants you to build them a workout plan from scratch. Walk them through a \
            short intake, one topic per turn, in this order: (1) what equipment they have \
            access to — this decides which movements you can program; (2) where they're \
            starting from — training history, current activity, anything that hurts; (3) what \
            they're after — their goal in their own words; (4) how many days a week they can \
            realistically train. If they volunteer several answers at once, don't re-ask. \
            When you have enough, propose a plan of 1–3 routines and briefly say why it fits. \
            After proposing, take feedback and revise.
            """
        case .reviseRoutine:
            let name = context.focusRoutineName.map { "\"\($0)\"" } ?? "this routine"
            return """
            The user wants to rework their routine \(name), shown below. First ask what \
            prompted the change — new equipment, more experience, less time, something hurting \
            — then propose a revised version. Keep the routine's name exactly the same so the \
            app updates it in place, and respect the user's current working levels: they are \
            demonstrated fitness, not suggestions. Progress conservatively from them.
            """
        case .reviseAll:
            return """
            The user wants you to look at their whole week of routines, shown below. Ask what \
            they want out of the review — balance, progression, a new goal, a schedule change \
            — before proposing. You may revise existing routines (keep their names exactly the \
            same so the app updates them in place) and add new ones. You cannot delete a \
            routine; if one should go, say so and the user will remove it in the app. Respect \
            current working levels — they are demonstrated fitness, not suggestions.
            """
        }
    }

    /// The movement vocabulary, grouped by equipment so the model can narrow by the user's
    /// answer. Small enough (dozens of entries) to bake into instructions — no lookup tool.
    static func vocabulary(_ library: [Exercise]) -> String {
        let groups = Dictionary(grouping: library) { $0.equipment.sorted() }
        let lines = groups
            .sorted { lhs, rhs in
                let l = lhs.key.map(\.rawValue).joined(separator: "+")
                let r = rhs.key.map(\.rawValue).joined(separator: "+")
                return l < r
            }
            .map { equipment, exercises in
                let label = equipment.map(\.displayName).joined(separator: " + ")
                let entries = exercises
                    .sorted { $0.id < $1.id }
                    .map { "  - \($0.id): \($0.name)\($0.kind.isHold ? " (hold)" : "")" }
                    .joined(separator: "\n")
                return "\(label):\n\(entries)"
            }
        return """
        These are the only movements the app can coach, grouped by required equipment. Only \
        propose movements whose equipment the user actually has. Running needs no equipment — \
        any routine may include adaptive run cards.

        \(lines.joined(separator: "\n"))
        """
    }

    /// Card semantics — the same rules the manual Claude round-trip uses
    /// (`RoutineExchange.primingPrompt`), which is the tested spec for this schema.
    static let schemaRules = """
    Plans are routines made of ordered cards. Card rules:
    - "type" is "run", "exercise", or "rest". Runs use "minutes" (the adaptive run block) plus \
    optional "warmupMinutes"/"cooldownMinutes" (walking, default 5 each); exercises use \
    "exercise" (an id from the list above) plus "reps" and "weightLb", or "holdSeconds" for \
    holds; rests use "seconds" plus optional "adaptive" (default true: rest ends early once \
    heart rate recovers, never below 3/4 of "seconds").
    - "rounds" repeats a routine's whole card list — that is how sets work. Put a rest card \
    between exercises (and one at the end for between rounds).
    - "days" are lowercase weekday names; "time" is "HH:mm" (24h). Keep a routine's "name" \
    stable when editing it; the app matches routines by name.
    """

    /// N6/N7 applied to the model: never promise what the app can't do; everything proposed
    /// is a starting seed the app will adapt, not a commitment.
    static let honestyRules = """
    Honesty rules: if the user's equipment or goal has no matching movements, say so plainly \
    rather than substituting something misleading. Do not invent movements, and do not promise \
    features the app doesn't have. Weights and reps you propose are starting seeds — the app \
    adjusts them automatically from real performance, so start conservative; the plan corrects \
    itself upward. Runs adapt to heart rate on their own; you set only the block length.
    """
}
