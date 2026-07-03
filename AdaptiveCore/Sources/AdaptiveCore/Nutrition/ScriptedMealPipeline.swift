import Foundation

/// The deterministic `MealPipeline` — `ScriptedCoachEngine` for meals. Backs the AdaptiveCore
/// unit tests (no model, no delays) and the phone's `-simulateMealScan` launch arg (visible
/// delays so "Looking up…" is demonstrable in the simulator, where Apple Intelligence can't
/// be granted).
public struct ScriptedMealPipeline: MealPipeline {

    public struct Script: Sendable {
        public var draft: MealDraft
        /// Returned by `identify` instead of `draft` when the capture carries a barcode —
        /// lets one scripted pipeline serve both demo paths, routed by capture content the
        /// way production is.
        public var barcodeDraft: MealDraft?
        /// Keyed by item id; items without an entry fall through to `estimate`.
        public var resolutions: [DraftItem.ID: ResolvedNutrition]
        public var identifyDelay: Duration?
        public var resolveDelay: Duration?
        /// Thrown by `identify` — for testing the failure/retry path.
        public var identifyError: Error?

        public init(
            draft: MealDraft,
            barcodeDraft: MealDraft? = nil,
            resolutions: [DraftItem.ID: ResolvedNutrition] = [:],
            identifyDelay: Duration? = nil,
            resolveDelay: Duration? = nil,
            identifyError: Error? = nil
        ) {
            self.draft = draft
            self.barcodeDraft = barcodeDraft
            self.resolutions = resolutions
            self.identifyDelay = identifyDelay
            self.resolveDelay = resolveDelay
            self.identifyError = identifyError
        }
    }

    public var availability: MealPipelineAvailability = .available
    let script: Script   // internal: `demo()` composes scripts from the canned parts

    public init(script: Script, availability: MealPipelineAvailability = .available) {
        self.script = script
        self.availability = availability
    }

    public func identify(_ capture: MealCapture) async throws -> MealDraft {
        if let delay = script.identifyDelay { try? await Task.sleep(for: delay) }
        if let error = script.identifyError { throw error }
        if !capture.barcodes.isEmpty, let barcodeDraft = script.barcodeDraft {
            return barcodeDraft
        }
        return script.draft
    }

    public func resolve(item: DraftItem, seller: Seller?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        if let delay = script.resolveDelay { try? await Task.sleep(for: delay) }
        if let scripted = script.resolutions[item.id] {
            return scripted
        }
        return try await estimate(item: item, capture: nil, answers: answers)
    }

    public func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        if let delay = script.resolveDelay { try? await Task.sleep(for: delay) }
        return ResolvedNutrition(
            facts: NutritionFacts(energy: .range(lowKcal: 350, highKcal: 600)),
            provenance: .estimate(assumptions: ["Typical single serving", "Standard preparation"])
        )
    }

    /// The scripted answer for an item, if the script has one (used by `ScriptedAdjudicator`
    /// to decline honestly — `nil` lets the ladder fall to the estimate rung, as production
    /// adjudication does when excerpts don't contain the answer).
    func scriptedResolution(for id: DraftItem.ID) -> ResolvedNutrition? {
        script.resolutions[id]
    }
}

// MARK: - Ladder rung adapters (compose a scripted MealResolver)

/// Wraps a `ScriptedMealPipeline` as the adjudicator rung so `-simulateMealScan` exercises
/// the same `MealResolver` orchestration the production build uses.
public struct ScriptedAdjudicator: ExcerptAdjudicator {
    private let pipeline: ScriptedMealPipeline
    public init(pipeline: ScriptedMealPipeline) { self.pipeline = pipeline }
    public func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
        pipeline.scriptedResolution(for: item.id)
    }
}

/// A searcher that always returns one canned excerpt (so the adjudicator rung engages).
public struct ScriptedSearcher: NutritionWebSearcher {
    public init() {}
    public func search(objective: String, queries: [String]) async throws -> [SearchExcerpt] {
        [SearchExcerpt(title: "Scripted result", url: nil, excerpt: "460 Cal")]
    }
}

/// The estimator rung backed by the same scripted pipeline.
public struct ScriptedEstimator: PlateEstimator {
    private let pipeline: ScriptedMealPipeline
    public init(pipeline: ScriptedMealPipeline) { self.pipeline = pipeline }
    public func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        try await pipeline.estimate(item: item, capture: capture, answers: answers)
    }
}

// MARK: - Canned demos (used by -simulateMealScan and the XCUI tests)

public extension ScriptedMealPipeline {

    /// Stable item ids so the demo resolutions and the UI tests can reference rows.
    enum DemoID {
        public static let salad = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
        public static let chicken = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
        public static let pasta = UUID(uuidString: "00000000-0000-0000-0000-00000000D003")!
        public static let curry = UUID(uuidString: "00000000-0000-0000-0000-00000000D004")!
        public static let cola = UUID(uuidString: "00000000-0000-0000-0000-00000000D005")!
    }

    /// A grocery receipt exercising everything at once: a database hit, a questionnaire item,
    /// a pre-unchecked pantry item (spec §4.3), and one honest estimate fallback.
    static func demoGroceryReceipt(delays: Bool = false) -> ScriptedMealPipeline {
        let draft = MealDraft(
            classification: .receipt,
            seller: Seller(name: "Trader Joe's", domainHint: "traderjoes.com"),
            items: [
                DraftItem(id: DemoID.salad, name: "Chicken Caesar Salad"),
                DraftItem(
                    id: DemoID.chicken,
                    name: "Rotisserie Chicken",
                    question: ClarifyingQuestion(
                        id: "portion",
                        prompt: "How much of it?",
                        options: [
                            .init(id: "quarter", label: "Quarter"),
                            .init(id: "half", label: "Half"),
                            .init(id: "whole", label: "Whole"),
                        ],
                        defaultOptionID: "quarter"
                    )
                ),
                DraftItem(id: DemoID.pasta, name: "Penne Pasta (box)", isChecked: false),
                DraftItem(id: DemoID.curry, name: "Deli Lentil Curry"),
            ]
        )
        return ScriptedMealPipeline(script: Script(
            draft: draft,
            resolutions: [
                DemoID.salad: ResolvedNutrition(
                    facts: NutritionFacts(
                        energy: .exact(kcal: 460),
                        proteinGrams: 39, carbGrams: 26, fatGrams: 23,
                        servingDescription: "1 salad"
                    ),
                    provenance: .database(name: "Open Food Facts", sourceURL: URL(string: "https://world.openfoodfacts.org"))
                ),
                DemoID.chicken: ResolvedNutrition(
                    facts: NutritionFacts(energy: .exact(kcal: 300), proteinGrams: 42, servingDescription: "quarter chicken"),
                    provenance: .verified(sourceURL: URL(string: "https://traderjoes.com"))
                ),
                // curry deliberately unresolved → falls to the estimate rung.
            ],
            identifyDelay: delays ? .milliseconds(600) : nil,
            resolveDelay: delays ? .milliseconds(500) : nil
        ))
    }

    /// The barcode fast path: one item, resolves as a database hit.
    static func demoBarcode(delays: Bool = false) -> ScriptedMealPipeline {
        let draft = MealDraft(
            classification: .barcode,
            seller: nil,
            items: [DraftItem(id: DemoID.cola, name: "Coca-Cola Classic 12 fl oz", barcode: "049000006346")]
        )
        return ScriptedMealPipeline(script: Script(
            draft: draft,
            resolutions: [
                DemoID.cola: ResolvedNutrition(
                    facts: NutritionFacts(energy: .exact(kcal: 140), carbGrams: 39, servingDescription: "1 can (355 ml)"),
                    provenance: .database(name: "Open Food Facts", sourceURL: URL(string: "https://world.openfoodfacts.org/product/049000006346"))
                ),
            ],
            identifyDelay: delays ? .milliseconds(400) : nil,
            resolveDelay: delays ? .milliseconds(500) : nil
        ))
    }

    /// The `-simulateMealScan` script: both demos behind one pipeline, routed by capture
    /// content exactly as production routes (barcode present → barcode draft).
    static func demo(delays: Bool = false) -> ScriptedMealPipeline {
        let receipt = demoGroceryReceipt(delays: delays)
        let barcode = demoBarcode(delays: delays)
        var script = receipt.script
        script.barcodeDraft = barcode.script.draft
        script.resolutions.merge(barcode.script.resolutions) { current, _ in current }
        return ScriptedMealPipeline(script: script)
    }

    /// Composes the scripted resolver the provider hands out under `-simulateMealScan` —
    /// same `MealResolver` orchestration as production, scripted rungs.
    func scriptedResolver() -> MealResolver {
        // Barcode items resolve through the scripted pipeline too (keyed by item id), so the
        // barcode rung is a scripted adjudicator behind a canned searcher.
        MealResolver(
            barcodeDB: nil,
            searcher: ScriptedSearcher(),
            adjudicator: ScriptedAdjudicator(pipeline: self),
            agent: nil,
            estimator: ScriptedEstimator(pipeline: self)
        )
    }
}
