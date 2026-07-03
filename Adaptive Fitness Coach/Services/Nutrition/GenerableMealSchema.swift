import Foundation
import FoundationModels
import AdaptiveCore

/// `@Generable` mirrors of the package's Nutrition models (the `GenerableRoutinePlan`
/// pattern): the macro must live in a FoundationModels target, AdaptiveCore stays
/// Foundation-only. Each mirror has exactly one `toPackage()` funnel; the phone unit target's
/// `MealSchemaDriftTests` pins mirror ↔ package together.

// MARK: - Stage 1–3: identify (receipt/label OCR → draft)

@Generable
struct GenerableMealDraft {
    @Guide(description: "Who sold the food — store, restaurant, or brand name as printed.")
    var sellerName: String?
    @Guide(description: "The seller's official website domain if you are confident of it, e.g. traderjoes.com. Omit when unsure.")
    var sellerDomain: String?
    @Guide(description: "The identified food and drink items. Never invent items not in the text.")
    var items: [GenerableDraftItem]
}

@Generable
struct GenerableDraftItem {
    @Guide(description: "The item name, abbreviations expanded, e.g. 'Chicken Caesar Salad'.")
    var name: String
    @Guide(description: "Quantity from the receipt line.", .range(1...20))
    var quantity: Int?
    @Guide(description: "true for ready-to-eat items the user is likely eating now; false for pantry/multi-meal groceries.")
    var eatingNow: Bool?
    @Guide(description: "A clarifying question, ONLY if the answer materially changes the calories. Most items need none.")
    var question: GenerableQuestion?
}

@Generable
struct GenerableQuestion {
    @Guide(description: "One short line, e.g. 'How much of it?'")
    var prompt: String
    @Guide(description: "2 to 4 short tappable options.", .count(2...4))
    var options: [String]
    @Guide(description: "Index of the most sensible default option.", .range(0...3))
    var defaultIndex: Int
}

// MARK: - Stage 4: excerpt adjudication / agentic result

@Generable
struct GenerableLookupResult {
    @Guide(description: "true only if an excerpt actually states the calories for this exact item. If not, false — never approximate.")
    var found: Bool
    @Guide(description: "Calories (kcal) for one serving, from the source.")
    var kcal: Double?
    @Guide(description: "Protein grams, if published.")
    var proteinGrams: Double?
    @Guide(description: "Carbohydrate grams, if published.")
    var carbGrams: Double?
    @Guide(description: "Total fat grams, if published.")
    var fatGrams: Double?
    @Guide(description: "The serving the numbers describe, as published, e.g. '1 salad (368 g)'.")
    var servingDescription: String?
    @Guide(description: "The URL of the source the number came from.")
    var sourceURL: String?
}

// MARK: - Stage 5: estimate

@Generable
struct GenerableEstimate {
    @Guide(description: "Low end of the honest calorie range for one serving.")
    var lowKcal: Double
    @Guide(description: "High end of the honest calorie range. Must be above lowKcal; be honest about portion uncertainty.")
    var highKcal: Double
    @Guide(description: "Rough protein grams midpoint, if estimable.")
    var proteinGrams: Double?
    @Guide(description: "Rough carbohydrate grams midpoint, if estimable.")
    var carbGrams: Double?
    @Guide(description: "Rough fat grams midpoint, if estimable.")
    var fatGrams: Double?
    @Guide(description: "The assumptions this estimate rests on, each one short line.", .count(1...5))
    var assumptions: [String]
}

// MARK: - Funnels to package types

extension GenerableMealDraft {
    func toPackage(classification: CaptureClassification) -> MealDraft {
        let seller = sellerName.map { Seller(name: $0, domainHint: sellerDomain?.lowercased()) }
        return MealDraft(
            classification: classification,
            seller: seller,
            items: items.enumerated().map { index, item in item.toPackage(index: index) }
        )
    }
}

extension GenerableDraftItem {
    func toPackage(index: Int) -> DraftItem {
        DraftItem(
            name: name,
            quantity: max(1, quantity ?? 1),
            isChecked: eatingNow ?? true,
            question: question?.toPackage(id: "item\(index)")
        )
    }
}

extension GenerableQuestion {
    func toPackage(id: String) -> ClarifyingQuestion? {
        let opts = options.enumerated().map { i, label in
            ClarifyingQuestion.Option(id: "\(id)-opt\(i)", label: label)
        }
        guard opts.count >= 2 else { return nil }
        let safeDefault = opts.indices.contains(defaultIndex) ? defaultIndex : 0
        return ClarifyingQuestion(
            id: id,
            prompt: prompt,
            options: opts,
            defaultOptionID: opts[safeDefault].id
        )
    }
}

extension GenerableLookupResult {
    /// `nil` when the model honestly reported failure (or emitted an unusable success) —
    /// the ladder falls through instead of logging a hollow number (C2/C3).
    func toPackage(seller: Seller?) -> ResolvedNutrition? {
        guard found, let kcal, kcal > 0 else { return nil }
        let url = sourceURL.flatMap(URL.init(string:))
        return ResolvedNutrition(
            facts: NutritionFacts(
                energy: .exact(kcal: kcal),
                proteinGrams: proteinGrams,
                carbGrams: carbGrams,
                fatGrams: fatGrams,
                servingDescription: servingDescription
            ),
            provenance: ProvenanceGrader.grade(sourceURL: url, seller: seller)
        )
    }
}

extension GenerableEstimate {
    func toPackage() -> ResolvedNutrition {
        // The mirror can't express low < high structurally; enforce it here (C3: estimates
        // are always honest ranges).
        let low = min(lowKcal, highKcal)
        var high = max(lowKcal, highKcal)
        if high <= low { high = low * 1.4 + 50 }
        return ResolvedNutrition(
            facts: NutritionFacts(
                energy: .range(lowKcal: low, highKcal: high),
                proteinGrams: proteinGrams,
                carbGrams: carbGrams,
                fatGrams: fatGrams
            ),
            provenance: .estimate(assumptions: assumptions)
        )
    }
}
