import Foundation

/// P6 "Export to Claude" context packs — engine-agnostic prompt + scoped context + response
/// format, composed as one paste-able string. Clipboard → the Claude app is today's
/// transport; a future Claude-API `CoachEngine` consumes the same packs unchanged.
///
/// Everything here is pure (no HealthKit, no UI): the phone gathers `HealthSnapshot` /
/// `NutritionDigest` through its own builders and passes plain values in, so every pack is
/// unit-tested on macOS — the same logic/plumbing split as `FitnessCalibration` vs
/// `HealthFitnessCalibrator`.
public enum ContextPackUseCase: String, CaseIterable, Sendable, Identifiable {
    /// Design or revise the training program ("for someone like me").
    case programDesign
    /// "How am I doing / is this enough?" — adherence, trajectory, intake vs burn.
    case checkIn
    /// Meal planning grounded in what the user actually eats.
    case mealPlanning
    /// One lift stopped moving — troubleshoot with its history.
    case plateau
    /// "Knee hurts / hotel gym" — rework the week under a constraint.
    case constraintRework
    /// Coming back after a gap — a gentle re-entry plan.
    case returnFromBreak

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .programDesign: return "Program design"
        case .checkIn: return "Check-in"
        case .mealPlanning: return "Meal planning"
        case .plateau: return "Plateau help"
        case .constraintRework: return "Work around a constraint"
        case .returnFromBreak: return "Return from a break"
        }
    }

    public var subtitle: String {
        switch self {
        case .programDesign: return "Revise the week with your earned levels"
        case .checkIn: return "How training and eating are actually going"
        case .mealPlanning: return "A plan built from what you really eat"
        case .plateau: return "Dig into one lift that stopped moving"
        case .constraintRework: return "Injury, travel, or new equipment"
        case .returnFromBreak: return "Ease back in after time off"
        }
    }

    /// The three cases whose answer comes back through the validated JSON import path.
    /// The rest ask for prose — honest about what the app can actually ingest.
    public var wantsJSONResponse: Bool {
        switch self {
        case .programDesign, .constraintRework, .returnFromBreak: return true
        case .checkIn, .mealPlanning, .plateau: return false
        }
    }

    /// The default scope this use case opens with — every toggle stays user-editable.
    public var preset: ContextPackScope {
        switch self {
        case .programDesign:
            return ContextPackScope(includeFitnessSnapshot: true, journalDays: 30)
        case .checkIn:
            return ContextPackScope(includeFitnessSnapshot: true, journalDays: 90,
                                    includeNutrition: true)
        case .mealPlanning:
            return ContextPackScope(includeRoutines: false, includeFitnessSnapshot: true,
                                    includeNutrition: true)
        case .plateau:
            return ContextPackScope(includeFitnessSnapshot: false, journalDays: 90)
        case .constraintRework:
            return ContextPackScope(includeFitnessSnapshot: false, journalDays: 30)
        case .returnFromBreak:
            return ContextPackScope(includeFitnessSnapshot: true, journalDays: 90)
        }
    }
}

/// What the user chose to include — drives both the pack's sections and the always-visible
/// includes-line.
public struct ContextPackScope: Sendable, Hashable {
    /// Include the routine set at all (meal planning defaults it off).
    public var includeRoutines: Bool
    /// nil = all routines; otherwise the chosen subset.
    public var routineIds: Set<UUID>?
    /// Aggregate vitals/fitness numbers (VO2max, resting HR, weight…). Health data — gated
    /// behind the one-time disclosure on the phone.
    public var includeFitnessSnapshot: Bool
    /// Days of progression-journal history to include (nil = none).
    public var journalDays: Int?
    /// Recent eating (daily totals + patterns). Health data, same disclosure.
    public var includeNutrition: Bool

    public init(
        includeRoutines: Bool = true,
        routineIds: Set<UUID>? = nil,
        includeFitnessSnapshot: Bool = false,
        journalDays: Int? = nil,
        includeNutrition: Bool = false
    ) {
        self.includeRoutines = includeRoutines
        self.routineIds = routineIds
        self.includeFitnessSnapshot = includeFitnessSnapshot
        self.journalDays = journalDays
        self.includeNutrition = includeNutrition
    }

    /// Whether this scope exports any Apple Health–derived data (drives the disclosure).
    public var includesHealthData: Bool { includeFitnessSnapshot || includeNutrition }
}

/// Aggregate fitness numbers read from Health on the phone — every field optional, and a
/// nil field renders as an omitted line, never a fabricated one (N6).
public struct HealthSnapshot: Codable, Sendable, Hashable {
    public var vo2Max: Double?
    public var restingHeartRate: Double?
    public var respiratoryRate: Double?
    public var bodyMassKg: Double?
    /// Weight change over the last ~30 days (kg, negative = lost).
    public var bodyMassDelta30dKg: Double?
    public var workoutsPerWeek90d: Double?
    public var daysSinceLastWorkout: Int?

    public init(
        vo2Max: Double? = nil,
        restingHeartRate: Double? = nil,
        respiratoryRate: Double? = nil,
        bodyMassKg: Double? = nil,
        bodyMassDelta30dKg: Double? = nil,
        workoutsPerWeek90d: Double? = nil,
        daysSinceLastWorkout: Int? = nil
    ) {
        self.vo2Max = vo2Max
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.bodyMassKg = bodyMassKg
        self.bodyMassDelta30dKg = bodyMassDelta30dKg
        self.workoutsPerWeek90d = workoutsPerWeek90d
        self.daysSinceLastWorkout = daysSinceLastWorkout
    }

    public var isEmpty: Bool {
        vo2Max == nil && restingHeartRate == nil && respiratoryRate == nil
            && bodyMassKg == nil && bodyMassDelta30dKg == nil
            && workoutsPerWeek90d == nil && daysSinceLastWorkout == nil
    }
}

/// Recent eating, aggregated per day on the phone from Health (never raw sample streams).
public struct NutritionDigest: Sendable, Hashable {
    public struct Day: Sendable, Hashable {
        public var date: Date
        public var totalKcal: Int
        public var proteinGrams: Int?

        public init(date: Date, totalKcal: Int, proteinGrams: Int? = nil) {
            self.date = date
            self.totalKcal = totalKcal
            self.proteinGrams = proteinGrams
        }
    }

    public var days: [Day]
    public var calorieTarget: Int?
    /// Most-frequent sellers/restaurants in the window — eating patterns, not a food log.
    public var frequentSellers: [String]

    public init(days: [Day], calorieTarget: Int? = nil, frequentSellers: [String] = []) {
        self.days = days
        self.calorieTarget = calorieTarget
        self.frequentSellers = frequentSellers
    }
}

/// Everything the composer reads — plain values, gathered by the phone.
public struct ContextPackInput {
    public var routines: [Routine]
    public var library: [Exercise]
    public var journal: [ProgressionJournalEntry]
    public var snapshot: HealthSnapshot?
    public var nutrition: NutritionDigest?
    /// "Now" for windows/relative dates — injected so packs are deterministic under test.
    public var now: Date

    public init(
        routines: [Routine],
        library: [Exercise] = ExerciseLibrary.all,
        journal: [ProgressionJournalEntry] = [],
        snapshot: HealthSnapshot? = nil,
        nutrition: NutritionDigest? = nil,
        now: Date = Date()
    ) {
        self.routines = routines
        self.library = library
        self.journal = journal
        self.snapshot = snapshot
        self.nutrition = nutrition
        self.now = now
    }
}

/// The composed export.
public struct ContextPack: Sendable, Hashable {
    public var title: String
    public var promptText: String
    /// The honest one-liner shown on the export sheet and under every export
    /// ("3 routines · fitness snapshot · 90-day progression · no meals").
    public var includesLine: String
}

public enum ContextPackComposer {
    public static func pack(
        useCase: ContextPackUseCase,
        scope: ContextPackScope,
        input: ContextPackInput
    ) -> ContextPack {
        var sections: [String] = [brief(for: useCase)]

        let routines = scopedRoutines(scope: scope, input: input)
        if scope.includeRoutines, !routines.isEmpty {
            sections.append("""
            My current routines from the app, as JSON (schema "\(RoutineExchange.schemaName)" \
            v\(RoutineExchange.schemaVersion)):

            ```json
            \(RoutineExchange.exportJSON(routines))
            ```
            """)
            if let progression = CoachContextBuilder.progressionSummary(routines, library: input.library) {
                sections.append(progression)
            }
        }

        if scope.includeFitnessSnapshot, let snapshot = input.snapshot, !snapshot.isEmpty {
            sections.append(snapshotSection(snapshot))
        }

        if let days = scope.journalDays {
            let history = journalSection(input.journal, days: days, now: input.now)
            if let history { sections.append(history) }
        }

        if scope.includeNutrition, let nutrition = input.nutrition, !nutrition.days.isEmpty {
            sections.append(nutritionSection(nutrition))
        }

        sections.append(responseFormat(for: useCase, library: input.library))

        return ContextPack(
            title: useCase.title,
            promptText: sections.joined(separator: "\n\n"),
            includesLine: includesLine(useCase: useCase, scope: scope, input: input)
        )
    }

    // MARK: - Sections

    static func brief(for useCase: ContextPackUseCase) -> String {
        switch useCase {
        case .programDesign:
            return """
            You're my personal trainer. Below is my current training week from the Adaptive \
            Fitness Coach app, with the working levels I've actually earned session by session. \
            Review the program for someone at exactly this demonstrated level — ask about my \
            goals if you need to, then propose a revised week.
            """
        case .checkIn:
            return """
            You're my personal trainer doing a periodic check-in. Below is what I've actually \
            done recently — my routines, how my working levels have moved (with the app's \
            reasons), and my recent eating. Tell me honestly how it's going: what's working, \
            what's stalling, and whether this is enough for my goals. Ask if you need my goals.
            """
        case .mealPlanning:
            return """
            You're my nutrition coach. Below is what I've actually been eating recently \
            (logged as I ate it), and my calorie target. Build me a realistic meal plan that \
            starts from these real habits — adjust rather than replace.
            """
        case .plateau:
            return """
            You're my personal trainer. One of my lifts has stopped moving — below is the \
            app's session-by-session record of every change it made and why, plus my current \
            levels. Diagnose the plateau and tell me specifically what to change.
            """
        case .constraintRework:
            return """
            You're my personal trainer. I need my week reworked around a constraint — I'll \
            describe it in my next message (injury, travel, equipment). Below is my current \
            week and earned levels; keep what still works and substitute what doesn't.
            """
        case .returnFromBreak:
            return """
            You're my personal trainer. I've been away from training for a while (the numbers \
            below show the gap). Propose a re-entry week that respects the break — ease back \
            in rather than resuming where I left off.
            """
        }
    }

    static func snapshotSection(_ s: HealthSnapshot) -> String {
        var lines: [String] = []
        if let v = s.vo2Max { lines.append("- VO2max: \(format(v)) ml/kg·min") }
        if let v = s.restingHeartRate { lines.append("- Resting heart rate: \(Int(v.rounded())) bpm") }
        if let v = s.respiratoryRate { lines.append("- Respiratory rate: \(format(v)) breaths/min") }
        if let v = s.bodyMassKg {
            var line = "- Weight: \(format(v)) kg"
            if let delta = s.bodyMassDelta30dKg {
                let signed = delta > 0 ? "+\(format(delta))" : format(delta)
                line += " (\(signed) kg over 30 days)"
            }
            lines.append(line)
        }
        if let v = s.workoutsPerWeek90d { lines.append("- Workouts per week (90-day average): \(format(v))") }
        if let v = s.daysSinceLastWorkout { lines.append("- Days since last workout: \(v)") }
        return "My fitness snapshot (from Apple Health):\n" + lines.joined(separator: "\n")
    }

    static func journalSection(_ journal: [ProgressionJournalEntry], days: Int, now: Date) -> String? {
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let window = journal.filter { $0.date >= cutoff }
        guard !window.isEmpty else { return nil }
        let lines = window.map { entry -> String in
            var line = "- \(entry.date.formatted(.dateTime.month(.abbreviated).day())) · "
                + "\(entry.subject) \(entry.changeText)"
            if let reason = entry.reason { line += " — \(reason)" }
            if let effort = entry.perceivedEffort { line += " (effort \(effort))" }
            if entry.kind == .declined { line += " [held by me]" }
            return line
        }
        return "How my working levels moved over the last \(days) days (the app's own record, "
            + "newest first):\n" + lines.joined(separator: "\n")
    }

    static func nutritionSection(_ n: NutritionDigest) -> String {
        var lines: [String] = []
        if let target = n.calorieTarget { lines.append("Daily calorie target: \(target) kcal.") }
        let dayLines = n.days.map { day -> String in
            var line = "- \(day.date.formatted(.dateTime.month(.abbreviated).day())): \(day.totalKcal) kcal"
            if let protein = day.proteinGrams { line += " · \(protein)g protein" }
            return line
        }
        lines.append("Recent days as logged:\n" + dayLines.joined(separator: "\n"))
        if !n.frequentSellers.isEmpty {
            lines.append("Places I actually eat from most: \(n.frequentSellers.joined(separator: ", ")).")
        }
        return "My recent eating (from Apple Health, logged as I ate):\n\n" + lines.joined(separator: "\n\n")
    }

    static func responseFormat(for useCase: ContextPackUseCase, library: [Exercise]) -> String {
        guard useCase.wantsJSONResponse else {
            return """
            Reply in plain prose — no JSON. (The app can only import complete routine sets; \
            this request isn't one, so a written answer is what I can actually use.)
            """
        }
        let vocab = library
            .map { "- \($0.id): \($0.name)\($0.kind.isHold ? " (hold)" : "")" }
            .joined(separator: "\n")
        return """
        When we've settled the plan, return the COMPLETE updated routine set as a single JSON \
        code block in the EXACT schema of the JSON above, so I can import it back into the app. \
        Rules:
        - Use only these exercise ids (the app can't add new movements yet):
        \(vocab)
        - "type" is "run", "exercise", or "rest". Runs use "minutes" (the adaptive run block) plus \
        optional "warmupMinutes"/"cooldownMinutes" (walking, default 5 each); exercises use \
        "exercise" (an id above) plus "reps" and "weightLb", or "holdSeconds" for holds; rests use \
        "seconds" plus optional "adaptive" (default true).
        - "rounds" repeats the whole card list (that's how sets work). "days" are lowercase weekday \
        names; "time" is "HH:mm" (24h). Keep a routine's "name" stable if you're editing it — the \
        app grafts my earned progression back by name.
        """
    }

    // MARK: - Includes line

    /// Public so the export sheet can render the line live while the user edits the scope,
    /// without composing the whole pack.
    public static func includesLine(
        useCase: ContextPackUseCase, scope: ContextPackScope, input: ContextPackInput
    ) -> String {
        var parts: [String] = []
        if scope.includeRoutines {
            let count = scopedRoutines(scope: scope, input: input).count
            parts.append(count == 1 ? "1 routine" : "\(count) routines")
        } else {
            parts.append("no routines")
        }
        parts.append(scope.includeFitnessSnapshot ? "fitness snapshot" : "no snapshot")
        if let days = scope.journalDays {
            parts.append("\(days)-day progression")
        } else {
            parts.append("no progression history")
        }
        parts.append(scope.includeNutrition ? "recent meals" : "no meals")
        return parts.joined(separator: " · ")
    }

    static func scopedRoutines(scope: ContextPackScope, input: ContextPackInput) -> [Routine] {
        guard scope.includeRoutines else { return [] }
        guard let ids = scope.routineIds else { return input.routines }
        return input.routines.filter { ids.contains($0.id) }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
