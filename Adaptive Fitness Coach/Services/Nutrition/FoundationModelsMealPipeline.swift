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
        // PCC without its entitlement is a FATAL ERROR, not .unavailable — never touch the
        // type unless the profile carries the grant (see PCCEntitlement).
        if PCCEntitlement.isGranted,
           case .available = PrivateCloudComputeLanguageModel().availability { return .available }
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
        // Typed entry: strip the calorie clause and date words BEFORE the model sees the
        // text (the stated number and the day are guarantees, not model behavior); the model
        // only normalizes the name/seller.
        if let typed = capture.typedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !typed.isEmpty {
            return await identifyTyped(typed)
        }
        if let barcode = capture.barcodes.first {
            return MealDraft(
                classification: .barcode,
                seller: nil,
                items: [DraftItem(name: "Scanned product", barcode: barcode)]
            )
        }
        // Plate photo (stage 5's entry): no barcode, no label, no readable text — the one
        // path where the user names the dish (inline, on the confirm screen) and the number
        // is an honest range. Portion is the assumption that most moves the estimate, so it's
        // asked up front as a deterministic C4 question, not assumed silently.
        guard !capture.ocrLines.isEmpty else {
            if capture.imageData != nil {
                return MealDraft(classification: .plate, seller: nil, items: [.plateFallback()])
            }
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
        var draft = response.content.toPackage(classification: .receipt)
        // Receipts print their transaction date — prefill the when-row (deterministic,
        // clamped; a miss costs one tap, a hallucination would be a wrong record).
        draft.capturedAt = ReceiptDateParser.parse(ocrLines: capture.ocrLines)
        return draft
    }

    /// The typed path: deterministic clause-stripping, then one model call to normalize.
    private func identifyTyped(_ typed: String) async -> MealDraft {
        let dated = TypedDatePhraseParser.parse(typed)
        let (strippedName, statedKcal) = StatedCalorieParser.parse(dated.cleanText)
        let statedFacts = statedKcal.map { NutritionFacts(energy: .exact(kcal: $0)) }
        // "from/at <seller>" is parsed deterministically too — the seller drives the whole
        // lookup ladder (seller-first queries, verified-on-their-domain grading), so naming
        // one must not hinge on the model filling an optional field. Division of labor: the
        // MODEL is the primary extractor (branding, spelling, domain — and the only reader
        // of receipts); the parser's candidate goes into the prompt as a hint, and code
        // floors on it only when the model returns no seller at all. Trade-off, accepted:
        // a model that considered the hint and deliberately returned nil is overridden —
        // omission is far likelier than rejection from a small model, and a wrong seller is
        // visible + editable while a dropped one silently degrades the lookup to generic.
        let sellerParse = TypedSellerParser.parse(strippedName)

        var draft: MealDraft
        if let session = try? makeSession(instructions: MealPromptBuilder.typedEntryInstructions()),
           let response = try? await session.respond(
               to: MealPromptBuilder.typedEntryPrompt(
                   text: strippedName,
                   sellerCandidate: sellerParse.seller?.name
               ),
               generating: GenerableMealDraft.self
           ),
           !response.content.items.isEmpty {
            draft = response.content.toPackage(classification: .typed)
        } else {
            // Model unavailable/failed: the typed path never dead-ends — log the text as-is
            // (minus the seller clause, which lives in `seller` below).
            let name = sellerParse.cleanText
            draft = MealDraft(
                classification: .typed,
                seller: nil,
                items: [DraftItem(name: name.prefix(1).uppercased() + name.dropFirst())]
            )
        }
        // Applied in code, after the funnel — the model can't drop either one.
        if draft.seller == nil { draft.seller = sellerParse.seller }
        if let statedFacts, !draft.items.isEmpty {
            draft.items[0].statedFacts = statedFacts
        }
        draft.capturedAt = dated.date
        draft.suggestedSlot = dated.slot
        return draft
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
        if PCCEntitlement.isGranted {
            let pcc = PrivateCloudComputeLanguageModel()
            if case .available = pcc.availability {
                return LanguageModelSession(model: pcc, tools: tools, instructions: instructions)
            }
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

    /// The excerpt budget for whichever model a fresh session will actually run on — sizing
    /// for the *preferred* model when the fallback runs was the spike's top failure (the
    /// on-device model is 4,096 tokens total).
    static var excerptBudget: ExcerptBudget {
        PCCEntitlement.isGranted ? .privateCloud : .onDevice
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
            to: MealPromptBuilder.adjudicationPrompt(
                item: item, seller: seller, answers: answers,
                excerpts: excerpts, budget: Self.excerptBudget
            ),
            generating: GenerableLookupResult.self
        )
        return response.content.toPackage(seller: seller)
    }
}

// MARK: - Ladder rung adapters

/// Rung 2b as an injectable — the resolver composes these; LookupLab measures them apart.
struct FoundationModelsAdjudicator: CandidateAdjudicator {
    let pipeline = FoundationModelsMealPipeline()

    func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
        try await pipeline.adjudicateExcerpts(item: item, seller: seller, excerpts: excerpts)
    }

    func adjudicateCandidates(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> [ResolvedAlternative] {
        try await pipeline.adjudicateCandidateExcerpts(item: item, seller: seller, excerpts: excerpts)
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
        let model: any LanguageModel = try {
            if PCCEntitlement.isGranted {
                let pcc = PrivateCloudComputeLanguageModel()
                if case .available = pcc.availability { return pcc }
            }
            // Same honest-unavailability discipline as makeSession(): never build a session
            // on an unavailable on-device model (surfaces as a raw session error otherwise).
            guard SystemLanguageModel.default.isAvailable else {
                throw CocoaError(.featureUnsupported)
            }
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

    /// P6 refresh/alternates: the same single call over the same excerpts, reporting up to
    /// a few DISTINCT matches (first = best) — different item, size, or preparation the
    /// excerpts also state numbers for. Same never-approximate contract per candidate.
    func adjudicateCandidateExcerpts(
        item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]
    ) async throws -> [ResolvedAlternative] {
        guard !excerpts.isEmpty else { return [] }
        let session = try makeSession(instructions: """
        You extract nutrition numbers from web search excerpts. You only report numbers an \
        excerpt actually states; a wrong-but-confident number is the one unacceptable \
        failure. Report the best match for the exact item asked about FIRST, then up to 3 \
        other distinct matches the excerpts also state numbers for (a different size, \
        variant, or closely related item) — only if genuinely present. Never repeat the \
        same item and number twice.
        """)
        let response = try await session.respond(
            to: MealPromptBuilder.adjudicationPrompt(
                item: item, seller: seller, answers: [],
                excerpts: excerpts, budget: Self.excerptBudget
            ),
            generating: GenerableLookupCandidates.self
        )
        return response.content.toPackage(seller: seller)
    }
}
