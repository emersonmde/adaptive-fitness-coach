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
        /// The payload declares a schema version newer than this build understands. Rejecting
        /// (rather than best-effort parsing) mirrors `WCMessageCodec`'s exact-version
        /// discipline — never silently mis-decode under old rules.
        case unsupportedVersion(Int)
        /// The envelope IS ours (schema matched) but a field failed to decode — surfaced
        /// with the decoder's detail so the user isn't told valid JSON "isn't JSON".
        case malformedRoutines(String)
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
        - "type" is "run", "exercise", or "rest". Runs use "minutes" (the adaptive run block) plus \
        optional "warmupMinutes"/"cooldownMinutes" (walking, default 5 each); exercises use \
        "exercise" (an id above) plus "reps" and "weightLb", or "holdSeconds" for holds; rests use \
        "seconds" plus optional "adaptive" (default true: rest ends early once heart rate \
        recovers, never below 3/4 of "seconds").
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
        try importRoutinesDetailed(fromJSON: text).routines
    }

    /// `importRoutines(fromJSON:)` plus an account of what validation dropped, so callers (the
    /// P3 coach) can be honest about a shrunken plan instead of silently swallowing cards.
    public struct DetailedImportResult: Sendable {
        public var routines: [Routine]
        /// Cards dropped for an unknown type or an exercise id outside the library (N6).
        public var droppedCardCount: Int
        /// Routines dropped because no card survived.
        public var droppedRoutineCount: Int
    }

    /// See `importRoutines(fromJSON:)` — same parsing and rules, with drop counts.
    public static func importRoutinesDetailed(fromJSON text: String) throws -> DetailedImportResult {
        guard let data = extractJSONObject(from: text) else { throw ExchangeError.notJSON }

        let decoder = JSONDecoder()
        let exchangeRoutines: [ExchangeRoutine]
        // Peek the envelope header first: once the schema is recognizably ours, a decode
        // failure is a *malformed payload* with a real reason — collapsing it into
        // `.notJSON` told users their demonstrably-JSON paste wasn't JSON.
        struct EnvelopePeek: Decodable { var schema: String?; var version: Int? }
        if let peek = try? decoder.decode(EnvelopePeek.self, from: data), peek.schema != nil {
            guard peek.schema == schemaName else { throw ExchangeError.unrecognizedSchema }
            guard let version = peek.version else { throw ExchangeError.malformedRoutines("missing version") }
            guard version <= schemaVersion else { throw ExchangeError.unsupportedVersion(version) }
            do {
                exchangeRoutines = try decoder.decode(Envelope.self, from: data).routines
            } catch let error as DecodingError {
                throw ExchangeError.malformedRoutines(Self.describeDecodingError(error))
            }
        } else if let bare = try? decoder.decode([ExchangeRoutine].self, from: data) {
            exchangeRoutines = bare   // tolerate a bare array (no envelope)
        } else {
            throw ExchangeError.notJSON
        }

        var routines: [Routine] = []
        var droppedCards = 0
        var droppedRoutines = 0
        for exchangeRoutine in exchangeRoutines {
            let builtCards = exchangeRoutine.cards.compactMap { $0.toWorkoutCard() }
            droppedCards += exchangeRoutine.cards.count - builtCards.count
            if builtCards.isEmpty {
                droppedRoutines += 1
            } else {
                routines.append(exchangeRoutine.toRoutine(cards: builtCards))
            }
        }
        guard !routines.isEmpty else { throw ExchangeError.noRoutines }
        return DetailedImportResult(
            routines: routines,
            droppedCardCount: droppedCards,
            droppedRoutineCount: droppedRoutines
        )
    }

    // MARK: - Card description (Markdown)

    private static func describe(_ card: WorkoutCard) -> String {
        switch card {
        case let .run(c):
            return "Run \(c.durationMinutes) min (adaptive, +\(c.warmupMinutes) warmup / +\(c.cooldownMinutes) cooldown)"
        case let .exercise(item):
            let name = ExerciseLibrary.exercise(id: item.exerciseId)?.name ?? item.exerciseId
            if let hold = item.holdSeconds { return "\(name) — \(Int(hold))s hold" }
            let load = item.seedWeight.map { " · \($0.displayString())" } ?? " · bodyweight"
            return "\(name) — \(item.reps ?? 0) reps\(load)"
        case let .rest(c):
            return "Rest \(Int(c.seconds))s"
        }
    }

    /// Pull the payload JSON out of arbitrary text. A fenced ```json block is preferred when
    /// present (prose like "here's [1] your update" would otherwise win the first-bracket
    /// scan and sink the whole import); otherwise fall back to the first balanced object/array.
    /// One human line for a Codable failure ("wrong type at routines[0].cards[2].minutes") —
    /// shown to the user via `ExchangeError.malformedRoutines`.
    private static func describeDecodingError(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath
                .map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
                .joined(separator: ".")
                .replacingOccurrences(of: ".[", with: "[")
            return joined.isEmpty ? "top level" : joined
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\" at \(path(context))"
        case .typeMismatch(_, let context):
            return "wrong value type at \(path(context))"
        case .valueNotFound(_, let context):
            return "null value at \(path(context))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return String(describing: error)
        }
    }

    private static func extractJSONObject(from text: String) -> Data? {
        if let fenceRange = text.range(of: "```json"),
           let fenced = extractFirstBalanced(from: String(text[fenceRange.upperBound...])) {
            return fenced
        }
        return extractFirstBalanced(from: text)
    }

    /// The first balanced top-level JSON object/array in `text`, as `Data`.
    private static func extractFirstBalanced(from text: String) -> Data? {
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

    /// Import: build a `Routine` around already-validated cards (see `toWorkoutCard()`).
    func toRoutine(cards builtCards: [WorkoutCard]) -> Routine {
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
    var minutes: Int?          // run: the adaptive run block, minutes
    var warmupMinutes: Int?    // run: walking warmup (default 5)
    var cooldownMinutes: Int?  // run: walking cooldown (default 5)
    var exercise: String?   // exercise slug
    var reps: Int?
    var weightLb: Double?
    var holdSeconds: Double?
    var seconds: Double?    // rest
    var adaptive: Bool?     // rest: HR-bounded (default true)

    /// Export: a `WorkoutCard` → its exchange form.
    init(_ card: WorkoutCard) {
        switch card {
        case let .run(c):
            type = "run"; minutes = c.durationMinutes
            warmupMinutes = c.warmupMinutes; cooldownMinutes = c.cooldownMinutes
        case let .exercise(item):
            type = "exercise"; exercise = item.exerciseId
            reps = item.reps; weightLb = item.seedWeight?.pounds; holdSeconds = item.holdSeconds
        case let .rest(c):
            type = "rest"; seconds = c.seconds; adaptive = c.adaptive
        }
    }

    /// Import: build a `WorkoutCard`, or nil to drop it (unknown type / unknown exercise id, N6).
    func toWorkoutCard() -> WorkoutCard? {
        switch type.lowercased() {
        case "run":
            // Run/walk seeds are deliberately NOT in the exchange schema — they're the user's
            // demonstrated fitness (progression state), not routine design, so Claude edits
            // never touch them. Import keeps the card's defaults; RoutineStore's name-merge
            // preserves ids only per-routine, so seeds reset on an edited run card — acceptable.
            return .run(RunCard(
                durationMinutes: max(1, minutes ?? 20),
                warmupMinutes: max(0, warmupMinutes ?? 5),
                cooldownMinutes: max(0, cooldownMinutes ?? 5)
            ))
        case "rest":
            return .rest(RestCard(seconds: max(1, seconds ?? 30), adaptive: adaptive ?? true))
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
    /// Parse "HH:mm" / "H:mm" (24h). nil for missing or out-of-range values — a nonsense
    /// time ("99:99") is rejected rather than clamped to a time the user never asked for.
    static func parse(_ string: String?) -> ScheduleTime? {
        guard let string else { return nil }
        let parts = string.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return ScheduleTime(hour: h, minute: m)
    }
}
