import Foundation

/// A portable, human- and Claude-friendly exchange format for routines — the workaround that lets
/// the user round-trip workouts through the Claude iOS app until in-app AI lands (P3).
///
/// There is no official API for the Claude app to read or write another app's data, so the loop is:
/// **export** the current routines (a self-describing JSON the user pastes/attaches into Claude,
/// wrapped in a priming prompt), iterate with Claude, then **import** the JSON Claude returns. The
/// app stays the system of record (N2) — import validates against the shared `ExerciseLibrary` and
/// drops anything it can't model (N6) rather than trusting the text blindly.
///
/// The schema is intentionally flat and readable (not `Routine`'s raw Codable) so Claude can emit it
/// reliably. All logic lives here in the package so it's unit-tested on macOS without either app.
public enum RoutineExchange {
    /// Identifies the payload so a paste of unrelated JSON is rejected rather than mis-imported.
    public static let schemaName = "adaptive-fitness-coach/routines"
    public static let schemaVersion = 1

    public enum ExchangeError: Error, Equatable {
        case notJSON
        case unrecognizedSchema
        case noRoutines
    }

    // MARK: - Export

    /// The routines as pretty exchange JSON (the envelope the importer round-trips).
    public static func exportJSON(_ routines: [Routine]) -> String {
        let envelope = Envelope(
            schema: schemaName,
            version: schemaVersion,
            routines: routines.map(ExchangeRoutine.init(_:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// A readable Markdown summary of the routines (for discussing with Claude or sharing as text).
    public static func markdown(_ routines: [Routine]) -> String {
        guard !routines.isEmpty else { return "_No routines yet._" }
        return routines.map { routine in
            var lines = ["## \(routine.name)"]
            var meta: [String] = []
            if !routine.repeatDays.isEmpty {
                meta.append(routine.repeatDays.sorted().map(\.shortName).joined(separator: " "))
            }
            if let t = routine.scheduleTime { meta.append(String(format: "%02d:%02d", t.hour, t.minute)) }
            if routine.rounds > 1 { meta.append("\(routine.rounds) rounds") }
            if !meta.isEmpty { lines.append("_\(meta.joined(separator: " · "))_") }
            for card in routine.cards { lines.append("- \(describe(card))") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// A ready-to-paste prompt: instructions + the valid exercise vocabulary + the current routines
    /// as JSON, telling Claude to return the complete updated set in the same schema for re-import.
    public static func primingPrompt(_ routines: [Routine]) -> String {
        let vocab = ExerciseLibrary.all
            .map { "- \($0.id): \($0.name)\($0.kind.isHold ? " (hold)" : "")" }
            .joined(separator: "\n")
        return """
        Here are my current workout routines from the Adaptive Fitness Coach app, as JSON \
        (schema "\(schemaName)" v\(schemaVersion)). Help me adjust them — ask about my goals and \
        experience, then propose changes.

        When we're done, return the COMPLETE updated set as a single JSON code block in this EXACT \
        schema so I can import it back into the app. Rules:
        - Use only these exercise ids (the app can't add new movements yet):
        \(vocab)
        - "type" is "run", "exercise", or "rest". Runs use "minutes"; exercises use "exercise" (an \
        id above) plus "reps" and "weightLb", or "holdSeconds" for holds; rests use "seconds".
        - "rounds" repeats the whole card list (that's how sets work). "days" are lowercase weekday \
        names; "time" is "HH:mm" (24h). Keep a routine's "name" stable if you're editing it.

        ```json
        \(exportJSON(routines))
        ```
        """
    }

    // MARK: - Import

    /// Parse exchange JSON (typically pasted from Claude) into routines. Tolerant of surrounding
    /// markdown/code fences and of a bare routines array. Throws on non-JSON, an unrecognized
    /// schema, or an empty set. Exercise cards with ids outside the library are dropped (N6); a
    /// routine that ends up with no cards is dropped.
    public static func importRoutines(fromJSON text: String) throws -> [Routine] {
        guard let data = extractJSONObject(from: text) else { throw ExchangeError.notJSON }

        let decoder = JSONDecoder()
        let exchangeRoutines: [ExchangeRoutine]
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            guard envelope.schema == schemaName else { throw ExchangeError.unrecognizedSchema }
            exchangeRoutines = envelope.routines
        } else if let bare = try? decoder.decode([ExchangeRoutine].self, from: data) {
            exchangeRoutines = bare   // tolerate a bare array (no envelope)
        } else {
            throw ExchangeError.notJSON
        }

        let routines = exchangeRoutines.compactMap { $0.toRoutine() }
        guard !routines.isEmpty else { throw ExchangeError.noRoutines }
        return routines
    }

    // MARK: - Card description (Markdown)

    private static func describe(_ card: WorkoutCard) -> String {
        switch card {
        case let .run(c):
            return "Run \(c.durationMinutes) min (adaptive)"
        case let .exercise(item):
            let name = ExerciseLibrary.exercise(id: item.exerciseId)?.name ?? item.exerciseId
            if let hold = item.holdSeconds { return "\(name) — \(Int(hold))s hold" }
            let load = item.seedWeight.map { " · \($0.displayString())" } ?? " · bodyweight"
            return "\(name) — \(item.reps ?? 0) reps\(load)"
        case let .rest(c):
            return "Rest \(Int(c.seconds))s"
        }
    }

    /// Pull the first top-level JSON object/array out of arbitrary text (handles ```json fences and
    /// chatter around the payload). Returns the raw `Data` to decode.
    private static func extractJSONObject(from text: String) -> Data? {
        let openers: [Character: Character] = ["{": "}", "[": "]"]
        guard let startIndex = text.firstIndex(where: { openers.keys.contains($0) }) else { return nil }
        let opener = text[startIndex]
        let closer = openers[opener]!
        var depth = 0
        var inString = false
        var escaped = false
        var i = startIndex
        while i < text.endIndex {
            let ch = text[i]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == opener { depth += 1 }
                else if ch == closer {
                    depth -= 1
                    if depth == 0 {
                        let slice = text[startIndex...i]
                        return String(slice).data(using: .utf8)
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}

// MARK: - Exchange DTOs (the on-the-wire shape)

private struct Envelope: Codable {
    var schema: String
    var version: Int
    var routines: [ExchangeRoutine]
}

private struct ExchangeRoutine: Codable {
    var name: String
    var rounds: Int?
    var days: [String]?
    var time: String?
    var cards: [ExchangeCard]

    init(name: String, rounds: Int?, days: [String]?, time: String?, cards: [ExchangeCard]) {
        self.name = name; self.rounds = rounds; self.days = days; self.time = time; self.cards = cards
    }

    /// Export: a `Routine` → its exchange form.
    init(_ routine: Routine) {
        name = routine.name
        rounds = routine.rounds > 1 ? routine.rounds : nil
        days = routine.repeatDays.isEmpty ? nil : routine.repeatDays.sorted().map { $0.fullName.lowercased() }
        time = routine.scheduleTime.map { String(format: "%02d:%02d", $0.hour, $0.minute) }
        cards = routine.cards.map(ExchangeCard.init(_:))
    }

    /// Import: build a `Routine`, validating cards against the library. Returns nil if no card survives.
    func toRoutine() -> Routine? {
        let builtCards = cards.compactMap { $0.toWorkoutCard() }
        guard !builtCards.isEmpty else { return nil }
        let parsedDays = Set((days ?? []).compactMap(DayOfWeek.parse(_:)))
        return Routine(
            name: name.isEmpty ? "Routine" : name,
            repeatDays: parsedDays,
            scheduleTime: ScheduleTime.parse(time),
            cards: builtCards,
            rounds: max(1, rounds ?? 1)
        )
    }
}

private struct ExchangeCard: Codable {
    var type: String
    var minutes: Int?       // run
    var exercise: String?   // exercise slug
    var reps: Int?
    var weightLb: Double?
    var holdSeconds: Double?
    var seconds: Double?    // rest

    /// Export: a `WorkoutCard` → its exchange form.
    init(_ card: WorkoutCard) {
        switch card {
        case let .run(c):
            type = "run"; minutes = c.durationMinutes
        case let .exercise(item):
            type = "exercise"; exercise = item.exerciseId
            reps = item.reps; weightLb = item.seedWeight?.pounds; holdSeconds = item.holdSeconds
        case let .rest(c):
            type = "rest"; seconds = c.seconds
        }
    }

    /// Import: build a `WorkoutCard`, or nil to drop it (unknown type / unknown exercise id, N6).
    func toWorkoutCard() -> WorkoutCard? {
        switch type.lowercased() {
        case "run":
            return .run(RunCard(durationMinutes: max(1, minutes ?? 30)))
        case "rest":
            return .rest(RestCard(seconds: max(1, seconds ?? 30)))
        case "exercise":
            guard let id = exercise, let entry = ExerciseLibrary.exercise(id: id) else { return nil }
            // Seed from the library (gets the right reps/weight/hold shape), then apply provided
            // values only to the dimensions the movement actually has (never fabricate one).
            var item = StrengthExerciseItem(from: entry)
            if item.reps != nil, let reps { item.reps = max(1, reps) }
            if item.seedWeight != nil, let weightLb { item.seedWeight = .lb(max(0, weightLb)) }
            if item.holdSeconds != nil, let holdSeconds { item.holdSeconds = max(1, holdSeconds) }
            return .exercise(item)
        default:
            return nil
        }
    }
}

// MARK: - Parsing helpers

private extension DayOfWeek {
    /// Parse a weekday from a loose string ("monday", "Mon", "MONDAY").
    static func parse(_ string: String) -> DayOfWeek? {
        let s = string.trimmingCharacters(in: .whitespaces).lowercased()
        return DayOfWeek.allCases.first { $0.fullName.lowercased() == s || $0.shortName.lowercased() == String(s.prefix(3)) }
    }
}

private extension ScheduleTime {
    /// Parse "HH:mm" / "H:mm" (24h), clamped to valid ranges. nil for missing/garbage.
    static func parse(_ string: String?) -> ScheduleTime? {
        guard let string else { return nil }
        let parts = string.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return ScheduleTime(hour: min(23, max(0, h)), minute: min(59, max(0, m)))
    }
}
