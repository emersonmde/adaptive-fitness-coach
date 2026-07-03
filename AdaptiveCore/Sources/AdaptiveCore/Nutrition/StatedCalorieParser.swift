import Foundation

/// Extracts a *stated* calorie count from typed/dictated text — "salmon caesar salad, 400
/// calories" → ("salmon caesar salad", 400). Deterministic and run in BOTH pipelines'
/// identify pre-pass, so "the stated number wins" is a structural guarantee, never a model
/// behavior (the model only ever sees the stripped name).
///
/// Rules: the clause must be trailing, and the number must be immediately followed by a
/// calorie unit word — "2 tacos" never parses; "400 cal", "400kcal", "400 calories" after a
/// comma/dash/space do.
public enum StatedCalorieParser {

    // Trailing clause: optional separator, optional hedge word, number, unit word, optional period.
    private static let pattern = try! NSRegularExpression(
        pattern: #"[,;–—-]?\s*(?:about |around |roughly |~)?(\d{2,4}(?:\.\d+)?)\s*k?cal(?:orie)?s?\.?\s*$"#,
        options: [.caseInsensitive]
    )

    public static func parse(_ text: String) -> (name: String, kcal: Double?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: fullRange),
              let numberRange = Range(match.range(at: 1), in: trimmed),
              let kcal = Double(trimmed[numberRange]), kcal > 0,
              let clauseRange = Range(match.range, in: trimmed) else {
            return (trimmed, nil)
        }
        var name = String(trimmed[..<clauseRange.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;–—-"))
        if name.isEmpty { name = trimmed }   // "400 calories" alone: keep the text as the name
        return (name, kcal)
    }
}
