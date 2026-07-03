import Foundation
import FoundationModels
import AdaptiveCore

/// The production `MealPipeline` plus the model-backed ladder rungs — Apple FoundationModels,
/// mirroring `FoundationModelsCoachEngine`: PCC preferred, on-device fallback, honest
/// unavailability, simulator always unavailable (`-simulateMealScan` is the sim path).
///
/// §5 context discipline: every stage-4 lookup is a *fresh* `LanguageModelSession` — the item
/// list is the state, nothing needs to survive between items; PCC's 32K never accumulates.
struct FoundationModelsMealPipeline: MealPipeline {

    var availability: MealPipelineAvailability {
        #if targetEnvironment(simulator)
        return .unavailable(reason: "Meal scanning needs Apple Intelligence on a real device. In the simulator, launch with -simulateMealScan.")
        #else
        if case .available = PrivateCloudComputeLanguageModel().availability { return .available }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        }
        #endif
    }

    // MARK: - Stages 1–3

    func identify(_ capture: MealCapture) async throws -> MealDraft {
        // Deterministic pre-passes first — no model call when the capture decides itself.
        if let barcode = capture.barcodes.first {
            return MealDraft(
                classification: .barcode,
                seller: nil,
                items: [DraftItem(name: "Scanned product", barcode: barcode)]
            )
        }
        guard !capture.ocrLines.isEmpty else {
            return MealDraft(classification: .unknown, seller: nil, items: [])
        }
        // Nutrition label: parse the panel deterministically — the printed label is the
        // seller's own data, so a successful parse short-circuits the whole ladder (C2).
        if let label = NutritionLabelParser.parse(ocrLines: capture.ocrLines) {
            return MealDraft(
                classification: .nutritionLabel,
                seller: nil,
                items: [DraftItem(
                    name: label.nameGuess ?? "Labeled item",   // inline-editable on confirm
                    labelFacts: label.facts
                )]
            )
        }

        let session = try makeSession(instructions: MealPromptBuilder.identifyInstructions())
        let response = try await session.respond(
            to: MealPromptBuilder.extractionPrompt(ocrLines: capture.ocrLines),
            generating: GenerableMealDraft.self
        )
        return response.content.toPackage(classification: .receipt)
    }

    // MARK: - Stage 4

    func resolve(item: DraftItem, seller: Seller?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        // The pipeline-level resolve is the adjudicator path; the full ladder (with barcode,
        // agent, and estimate rungs around it) is composed in MealPipelineProvider.
        let searcher = ParallelSearchClient()
        let excerpts = try await searcher.search(
            objective: MealPromptBuilder.searchObjective(item: item, seller: seller),
            queries: MealPromptBuilder.searchQueries(item: item, seller: seller)
        )
        if let judged = try await adjudicate(item: item, seller: seller, answers: answers, excerpts: excerpts) {
            return judged
        }
        return try await estimate(item: item, capture: nil, answers: answers)
    }

    // MARK: - Stage 5

    func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        let session = try makeSession(instructions: MealPromptBuilder.estimateInstructions())
        let response = try await session.respond(
            to: MealPromptBuilder.estimatePrompt(
                item: item,
                ocrLines: capture?.ocrLines ?? [],
                answers: answers
            ),
            generating: GenerableEstimate.self
        )
        return response.content.toPackage()
    }

    // MARK: - Session plumbing

    private func makeSession(instructions: String, tools: [any Tool] = []) throws -> LanguageModelSession {
        #if targetEnvironment(simulator)
        throw CocoaError(.featureUnsupported)
        #else
        let pcc = PrivateCloudComputeLanguageModel()
        if case .available = pcc.availability {
            return LanguageModelSession(model: pcc, tools: tools, instructions: instructions)
        }
        if SystemLanguageModel.default.isAvailable {
            return LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
        }
        throw CocoaError(.featureUnsupported)
        #endif
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This iPhone doesn't support Apple Intelligence, which powers meal lookups."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to scan meals."
        case .modelNotReady:
            "The Apple Intelligence model is still getting ready — try again in a bit."
        @unknown default:
            "Apple Intelligence isn't available right now."
        }
    }

    private func adjudicate(
        item: DraftItem,
        seller: Seller?,
        answers: [QuestionAnswer],
        excerpts: [SearchExcerpt]
    ) async throws -> ResolvedNutrition? {
        guard !excerpts.isEmpty else { return nil }
        let session = try makeSession(instructions: """
        You extract nutrition numbers from web search excerpts. You only report a number an \
        excerpt actually states for the exact item asked about; otherwise you report the \
        lookup failed. A wrong-but-confident number is the one unacceptable failure.
        """)
        let response = try await session.respond(
            to: MealPromptBuilder.adjudicationPrompt(item: item, seller: seller, answers: answers, excerpts: excerpts),
            generating: GenerableLookupResult.self
        )
        return response.content.toPackage(seller: seller)
    }
}

// MARK: - Ladder rung adapters

/// Rung 2b as an injectable — the resolver composes these; LookupLab measures them apart.
struct FoundationModelsAdjudicator: ExcerptAdjudicator {
    let pipeline = FoundationModelsMealPipeline()

    func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
        try await pipeline.adjudicateExcerpts(item: item, seller: seller, excerpts: excerpts)
    }
}

/// Rung 3: the model drives `web_search`/`fetch_page` itself ("browser-use-lite", CQ3d).
/// Ships behind the spike's verdict — `MealPipelineProvider` decides whether this is wired.
struct FoundationModelsAgenticLookup: AgenticLookup {
    let searcher: any NutritionWebSearcher

    func research(item: DraftItem, seller: Seller?) async throws -> ResolvedNutrition? {
        #if targetEnvironment(simulator)
        throw CocoaError(.featureUnsupported)
        #else
        let pcc = PrivateCloudComputeLanguageModel()
        let model: any LanguageModel = {
            if case .available = pcc.availability { return pcc }
            return SystemLanguageModel.default
        }()
        let session = LanguageModelSession(
            model: model,
            tools: [WebSearchTool(searcher: searcher), FetchPageTool()],
            instructions: MealPromptBuilder.agentInstructions(item: item, seller: seller)
        )
        let response = try await session.respond(
            to: "Find the nutrition information now, then report the result.",
            generating: GenerableLookupResult.self
        )
        return response.content.toPackage(seller: seller)
        #endif
    }
}

/// Rung 4 as an injectable.
struct FoundationModelsEstimator: PlateEstimator {
    let pipeline = FoundationModelsMealPipeline()

    func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
        try await pipeline.estimate(item: item, capture: capture, answers: answers)
    }
}

extension FoundationModelsMealPipeline {
    /// Internal seam so the adjudicator rung struct can reach the private implementation.
    func adjudicateExcerpts(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
        try await adjudicate(item: item, seller: seller, answers: [], excerpts: excerpts)
    }
}
