import Foundation

/// Shrinks search excerpts to fit a model's context without losing the lines that answer the
/// question (§5 context discipline, extended to the search rung after the on-device spike:
/// Apple's local model is 4,096 tokens *total* — untrimmed excerpts blew it on most items).
///
/// Same philosophy as `PageReducer`: the answer lives in a few lines (a nutrition-table row,
/// a "460 Cal" fragment); everything else is navigation and related-items noise. Keep lines
/// that mention the item's terms or nutrition vocabulary (+ one neighbor for context), then
/// cap hard.
/// How much excerpt material a model call may carry — sized by the *running* model, not the
/// preferred one (the on-device model is 4,096 tokens total; PCC is 32K).
public struct ExcerptBudget: Sendable {
    public var maxExcerpts: Int
    public var perExcerptCharacters: Int
    public var totalCharacters: Int

    public init(maxExcerpts: Int, perExcerptCharacters: Int, totalCharacters: Int) {
        self.maxExcerpts = maxExcerpts
        self.perExcerptCharacters = perExcerptCharacters
        self.totalCharacters = totalCharacters
    }

    /// ~1,500 prompt tokens of excerpts: fits the local model's 4,096 total alongside
    /// instructions and a structured response.
    public static let onDevice = ExcerptBudget(maxExcerpts: 4, perExcerptCharacters: 1_800, totalCharacters: 6_000)
    /// PCC's 32K leaves room to be generous — more excerpts beats a second search.
    public static let privateCloud = ExcerptBudget(maxExcerpts: 5, perExcerptCharacters: 8_000, totalCharacters: 32_000)
}

public enum ExcerptReducer {

    /// Vocabulary that marks a line as nutrition-bearing regardless of item terms.
    private static let nutritionMarkers = [
        "cal", "kcal", "protein", "carb", "fat ", "fat|", "serving", "sodium", "sugar", "fiber",
    ]

    public static func reduce(
        _ excerpts: [SearchExcerpt],
        query: String,
        budget: ExcerptBudget
    ) -> [SearchExcerpt] {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        var remaining = budget.totalCharacters
        var reduced: [SearchExcerpt] = []
        for excerpt in excerpts.prefix(budget.maxExcerpts) {
            guard remaining > 200 else { break }   // a sliver of a new excerpt helps nobody
            let excerptBudget = min(budget.perExcerptCharacters, remaining)
            let body = reduceBody(excerpt.excerpt, terms: terms, maxCharacters: excerptBudget)
            guard !body.isEmpty else { continue }
            remaining -= body.count
            reduced.append(SearchExcerpt(title: excerpt.title, url: excerpt.url, excerpt: body))
        }
        return reduced
    }

    static func reduceBody(_ text: String, terms: [String], maxCharacters: Int) -> String {
        if text.count <= maxCharacters { return text }

        let lines = text.components(separatedBy: "\n")
        var keep = [Bool](repeating: false, count: lines.count)
        for (index, line) in lines.enumerated() {
            let lowered = line.lowercased()
            let matchesTerm = terms.contains { lowered.contains($0) }
            let matchesNutrition = nutritionMarkers.contains { lowered.contains($0) }
            if matchesTerm || matchesNutrition {
                keep[index] = true
                if index > 0 { keep[index - 1] = true }              // one neighbor of context
                if index + 1 < lines.count { keep[index + 1] = true }
            }
        }

        var selected = zip(lines, keep).filter(\.1).map(\.0)
        // Nothing matched (unusual page shape) → fall back to the head; it names the item.
        if selected.isEmpty {
            selected = lines
        }

        var output = ""
        for line in selected {
            let addition = output.isEmpty ? line : "\n" + line
            if output.count + addition.count > maxCharacters {
                let room = maxCharacters - output.count
                if room > 80 { output += String(addition.prefix(room)) + "…" }
                break
            }
            output += addition
        }
        return output
    }
}
