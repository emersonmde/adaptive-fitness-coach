import Foundation
import Testing
@testable import AdaptiveCore

/// The excerpt reducer (spike follow-up): oversized search excerpts must shrink to the
/// running model's budget without losing the nutrition-bearing lines.
struct ExcerptReducerTests {

    /// A realistic aggregator excerpt: the answer is 3 lines inside 40 lines of menu noise.
    private var noisyExcerpt: SearchExcerpt {
        var lines = (1...20).map { "Related menu item number \($0) with a long descriptive name" }
        lines.append("Apple Pecan Chicken Salad, full size")
        lines.append("|Amount Per Serving |460 Cal |")
        lines.append("|Protein |39 g |")
        lines.append(contentsOf: (1...20).map { "Footer navigation link \($0) about the company" })
        return SearchExcerpt(title: "Calories in Salad", url: nil, excerpt: lines.joined(separator: "\n"))
    }

    @Test func keepsNutritionLinesUnderTightBudget() {
        let reduced = ExcerptReducer.reduce(
            [noisyExcerpt],
            query: "Apple Pecan Chicken Salad calories Wendy's",
            budget: ExcerptBudget(maxExcerpts: 4, perExcerptCharacters: 600, totalCharacters: 600)
        )
        #expect(reduced.count == 1)
        #expect(reduced[0].excerpt.count <= 600)
        #expect(reduced[0].excerpt.contains("460 Cal"))
        #expect(reduced[0].excerpt.contains("Protein"))
        #expect(!reduced[0].excerpt.contains("Footer navigation link 15"))
    }

    @Test func totalBudgetBoundsAllExcerpts() {
        let many = Array(repeating: noisyExcerpt, count: 6)
        let budget = ExcerptBudget(maxExcerpts: 5, perExcerptCharacters: 1_000, totalCharacters: 2_000)
        let reduced = ExcerptReducer.reduce(many, query: "salad calories", budget: budget)
        let total = reduced.reduce(0) { $0 + $1.excerpt.count }
        #expect(total <= 2_000)
        #expect(reduced.count <= 5)
    }

    @Test func smallExcerptsPassThroughUntouched() {
        let small = SearchExcerpt(title: "t", excerpt: "Big Mac: 590 calories per burger.")
        let reduced = ExcerptReducer.reduce(
            [small], query: "Big Mac calories",
            budget: .onDevice
        )
        #expect(reduced[0].excerpt == small.excerpt)
    }

    @Test func noMatchesFallsBackToHead() {
        let unrelated = SearchExcerpt(
            title: "t",
            excerpt: (1...50).map { "generic line \($0) about weather" }.joined(separator: "\n")
        )
        let reduced = ExcerptReducer.reduce(
            [unrelated], query: "zzzz qqqq",
            budget: ExcerptBudget(maxExcerpts: 1, perExcerptCharacters: 300, totalCharacters: 300)
        )
        #expect(reduced.count == 1)
        #expect(reduced[0].excerpt.contains("generic line 1"))
        #expect(reduced[0].excerpt.count <= 300)
    }

    @Test func adjudicationPromptRespectsBudget() {
        // The end-to-end check: a prompt built from six giant excerpts stays model-sized.
        let item = DraftItem(name: "Apple Pecan Chicken Salad")
        let prompt = MealPromptBuilder.adjudicationPrompt(
            item: item,
            seller: Seller(name: "Wendy's", domainHint: "wendys.com"),
            answers: [],
            excerpts: Array(repeating: noisyExcerpt, count: 6),
            budget: .onDevice
        )
        // Device-measured: tables tokenize at ~2.5–3 chars/token, and the window also holds
        // instructions + output. 5,100 chars ≈ ≤2,000 prompt tokens — real headroom in 4,096.
        #expect(prompt.count < 5_100, "prompt is \(prompt.count) chars")
        #expect(prompt.contains("460 Cal"))
    }

    @Test func adjudicationPromptCarriesTheSourcePreferenceLadder() {
        // Pin the graded-fallback policy (user decision, 2026-07-03): seller's own data
        // first, this seller's item in a database second, a comparable GENERIC dish only
        // when the seller publishes nothing — never a flat refusal that skips a usable
        // generic number and dead-ends into the estimate range.
        let prompt = MealPromptBuilder.adjudicationPrompt(
            item: DraftItem(name: "Chicken Caesar Salad"),
            seller: Seller(name: "Saladworks"),
            answers: [],
            excerpts: [SearchExcerpt(title: "t", excerpt: "e")],
            budget: .privateCloud
        )
        #expect(prompt.contains("Seller: Saladworks"))
        #expect(prompt.contains("strict order"))
        #expect(prompt.contains("comparable generic version"))
        #expect(prompt.contains("say the lookup failed"))
    }

    @Test func typedPromptHandsTheModelTheParsedSellerCandidate() {
        // Parser + model cooperate: the structural "from X" read goes into the prompt as a
        // hint the model confirms/corrects/rejects — not a silent post-hoc override.
        let hinted = MealPromptBuilder.typedEntryPrompt(
            text: "chicken ceaser salad from salad works",
            sellerCandidate: "Salad Works"
        )
        #expect(hinted.contains("appears to name the seller \"Salad Works\""))
        #expect(hinted.contains("reject it"))
        // No candidate → no hint block.
        #expect(!MealPromptBuilder.typedEntryPrompt(text: "chicken salad").contains("appears to name"))
    }
}
