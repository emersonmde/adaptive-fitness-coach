import Foundation
import Testing
@testable import AdaptiveCore

/// The deterministic Nutrition Facts panel parser (Slice C) — OCR-shaped fixtures, including
/// the column-split and unit-hugging quirks Vision actually produces.
struct NutritionLabelParserTests {

    private let cleanLabel = [
        "GREEK YOGURT",
        "Plain · Whole Milk",
        "Nutrition Facts",
        "8 servings per container",
        "Serving size 2/3 cup (170g)",
        "Amount per serving",
        "Calories 190",
        "% Daily Value*",
        "Total Fat 9g 12%",
        "Saturated Fat 6g 30%",
        "Cholesterol 35mg 12%",
        "Sodium 65mg 3%",
        "Total Carbohydrate 9g 3%",
        "Total Sugars 9g",
        "Protein 17g 34%",
    ]

    @Test func parsesACleanPanel() throws {
        let parsed = try #require(NutritionLabelParser.parse(ocrLines: cleanLabel))
        #expect(parsed.facts.energy == .exact(kcal: 190))
        #expect(parsed.facts.fatGrams == 9)
        #expect(parsed.facts.carbGrams == 9)
        #expect(parsed.facts.proteinGrams == 17)
        #expect(parsed.facts.servingDescription == "2/3 cup (170g)")
        #expect(parsed.nameGuess == "Plain · Whole Milk")   // longest name-like line above the panel
    }

    @Test func columnSplitCaloriesParse() throws {
        // OCR often splits the big calories row into two lines.
        let split = ["Nutrition Facts", "Serving size 1 bar (68g)", "Calories", "250", "Total Fat 5g"]
        let parsed = try #require(NutritionLabelParser.parse(ocrLines: split))
        #expect(parsed.facts.energy == .exact(kcal: 250))
        #expect(parsed.facts.fatGrams == 5)
    }

    @Test func percentDailyValueIsNeverTheValue() throws {
        // "Total Fat 10%" alone (value column lost) must not read 10 as grams… the first
        // number is inside a percent — skip it, take none.
        let tricky = ["Nutrition Facts", "Calories 100", "Total Fat 10%"]
        let parsed = try #require(NutritionLabelParser.parse(ocrLines: tricky))
        #expect(parsed.facts.fatGrams == nil)
    }

    @Test func noPanelHeadingIsNil() {
        #expect(NutritionLabelParser.parse(ocrLines: ["TRADER JOE'S", "CHKN CSR SLD 5.99"]) == nil)
    }

    @Test func headingWithoutCaloriesIsNil() {
        // Half a label (blurry photo) must flow to the normal ladder, not log a hollow entry.
        #expect(NutritionLabelParser.parse(ocrLines: ["Nutrition Facts", "Serving size 1 cup"]) == nil)
    }

    @Test func labelFactsShortCircuitTheLadderAsVerified() async {
        // The full Slice C path: parsed label → resolver returns verified with no rungs wired.
        let parsed = NutritionLabelParser.parse(ocrLines: cleanLabel)!
        let item = DraftItem(name: "Greek Yogurt", labelFacts: parsed.facts)
        let resolver = MealResolver(
            barcodeDB: nil, searcher: nil, adjudicator: nil, agent: nil,
            estimator: FailingEstimator()
        )
        let (resolved, rung) = await resolver.resolve(item: item, seller: nil, capture: nil, answers: [])
        #expect(rung == .printedLabel)
        #expect(resolved.facts.energy == .exact(kcal: 190))
        guard case .verified = resolved.provenance else {
            Issue.record("printed label must grade verified"); return
        }
    }

    private struct FailingEstimator: PlateEstimator {
        func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
            Issue.record("estimator must not be reached for a labeled item")
            throw CocoaError(.featureUnsupported)
        }
    }
}
