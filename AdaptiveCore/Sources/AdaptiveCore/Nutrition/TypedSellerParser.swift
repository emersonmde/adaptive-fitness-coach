import Foundation

/// Deterministic "from/at <seller>" extraction for typed entries — the seller sibling of
/// `StatedCalorieParser` and `TypedDatePhraseParser`. The seller is the highest-value signal
/// the lookup ladder has (it turns "chicken caesar salad calories" into "Saladworks chicken
/// caesar salad calories" and lets the grader mark the seller's own domain `.verified`), so
/// naming one must be a *guarantee*, not model behavior: on-device the small model was seen
/// normalizing "chicken ceaser salad from salad works" into a clean item name while silently
/// dropping the seller. The model still runs and may refine what we parse (official branding,
/// domain hint); this parser makes sure the seller exists at all.
///
/// Trailing-clause-only, like the calorie parser: only a `from`/`at` clause at the END of the
/// text is treated as a seller ("salad from the deli counter at Wegmans" → "Wegmans"), so
/// mid-sentence prose is never rewritten.
public enum TypedSellerParser {

    public struct Result: Sendable, Equatable {
        /// The text with the seller clause removed (untouched when no seller parsed).
        public var cleanText: String
        public var seller: Seller?
    }

    /// Trailing clauses that read like "from X" but never name a seller — places food comes
    /// from at home, and preparation sources ("from a mix", "from powder").
    private static let nonSellers: Set<String> = [
        "scratch", "home", "work", "the office", "the fridge", "the freezer",
        "leftovers", "last night", "the garden", "my garden",
        "powder", "concentrate", "a mix", "the mix", "a box", "the box",
        "a can", "the can", "a jar", "the jar", "a packet", "the packet",
        "the oven", "the microwave", "the grill", "the tap",
    ]

    public static func parse(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        // The LAST "from"/"at" wins ("the deli counter at Wegmans" → "Wegmans") — search
        // both markers and take whichever clause starts later in the text.
        var best: (markerRange: Range<String.Index>, clause: String)?
        for marker in [" from ", " at "] {
            guard let range = lowered.range(of: marker, options: .backwards) else { continue }
            let clause = String(trimmed[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if best == nil || range.lowerBound > best!.markerRange.lowerBound {
                best = (range, clause)
            }
        }
        guard let (markerRange, rawClause) = best else { return Result(cleanText: trimmed) }

        // A seller clause is a short name, not a sentence: 1–4 words, no digits (digits mean
        // a quantity/measurement, not a place), non-empty, and not a known non-seller.
        let clause = rawClause.hasSuffix(".") ? String(rawClause.dropLast()) : rawClause
        let words = clause.split(separator: " ")
        guard !words.isEmpty, words.count <= 4,
              clause.rangeOfCharacter(from: .decimalDigits) == nil,
              !nonSellers.contains(clause.lowercased()) else {
            return Result(cleanText: trimmed)
        }
        // "the" prefix is articleware, not the name ("from the Cheesecake Factory").
        let name = clause.lowercased().hasPrefix("the ") && words.count > 1
            ? String(clause.dropFirst(4))
            : clause

        let itemText = String(trimmed[..<markerRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "from Saladworks" alone (no food before it) isn't an entry we can log.
        guard !itemText.isEmpty else { return Result(cleanText: trimmed) }

        return Result(cleanText: itemText, seller: Seller(name: titleCased(name)))
    }

    /// "salad works" → "Salad Works". Words the user already capitalized are kept verbatim
    /// (they typed the brand's casing; the model may still refine to official branding).
    private static func titleCased(_ name: String) -> String {
        name.split(separator: " ")
            .map { $0.first?.isUppercase == true ? String($0) : $0.capitalized }
            .joined(separator: " ")
    }
}
