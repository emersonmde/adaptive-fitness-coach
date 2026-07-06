import Foundation

/// The stage-4 lookup ladder (CQ1/CQ3 decision): rungs in cost order, each injected as a
/// protocol so the ordering, skipping, and bottom-rung guarantee are unit-testable with fakes
/// and the phone can disable a rung (`nil`) without the callers noticing.
///
///   1. barcode → open database (Open Food Facts REST — no LLM at all)
///   2. keyless web search → one structured model call adjudicating the excerpts
///   3. agentic tool loop (search + fetch, §5 context discipline) — ships disabled until the
///      on-device spike justifies it
///   4. honest estimate (range + assumptions)
///
/// A parsed nutrition label short-circuits the whole ladder as `.verified` — the seller's own
/// printed data outranks anything we could look up.
///
/// The resolver NEVER throws to the UI: the bottom rung always answers, because a labeled
/// range beats a spinner that ends in an error (C3/N6 — never fabricate, never dead-end).

/// Rung 1: barcode → product database. `nil` = not found / no usable energy value.
public protocol BarcodeNutritionDatabase: Sendable {
    func lookup(barcode: String) async throws -> ResolvedNutrition?
}

/// One search hit the adjudicator can reason over. Excerpts are LLM-optimized snippets
/// (Parallel Search returns nutrition tables inline — the spike showed answers usually live
/// here, no fetch needed).
public struct SearchExcerpt: Sendable, Hashable {
    public var title: String
    public var url: URL?
    public var excerpt: String

    public init(title: String, url: URL? = nil, excerpt: String) {
        self.title = title
        self.url = url
        self.excerpt = excerpt
    }
}

/// Rung 2a: keyless web search (Parallel Search MCP in production).
public protocol NutritionWebSearcher: Sendable {
    func search(objective: String, queries: [String]) async throws -> [SearchExcerpt]
}

/// Rung 2b: one structured model call over the excerpts. `nil` = the excerpts didn't contain
/// a defensible number (fall through, don't guess — C2).
public protocol ExcerptAdjudicator: Sendable {
    func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition?
}

/// One pickable lookup candidate (P6 refresh/alternates): a name/serving the user can tell
/// apart plus the number and its provenance, inseparably.
public struct ResolvedAlternative: Sendable, Hashable {
    /// What distinguishes this candidate ("Chicken Caesar Salad — half size").
    public var name: String
    public var nutrition: ResolvedNutrition

    public init(name: String, nutrition: ResolvedNutrition) {
        self.name = name
        self.nutrition = nutrition
    }
}

/// Rung 2b, multi-candidate (P6): the same single model call over the same excerpts, but
/// reporting up to a few DISTINCT adjudicated matches (first = best) instead of only the
/// top one — the wrong-item/wrong-size confusion lives inside the excerpt set the
/// adjudicator already read, so one pass surfaces the honest alternatives. Never raw
/// excerpts in the UI: every candidate here passed adjudication (N6).
public protocol CandidateAdjudicator: ExcerptAdjudicator {
    /// Empty = nothing defensible (fall through, same contract as `adjudicate` returning nil).
    func adjudicateCandidates(
        item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]
    ) async throws -> [ResolvedAlternative]
}

/// Rung 3: the agentic loop (model drives search/fetch tools). `nil` result = gave up honestly.
public protocol AgenticLookup: Sendable {
    func research(item: DraftItem, seller: Seller?) async throws -> ResolvedNutrition?
}

/// Rung 4: the estimate fallback. Never optional and never fails — the guarantee the whole
/// ladder rests on. Implementations must return `.estimate` provenance with a range.
public protocol PlateEstimator: Sendable {
    func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition
}

public struct MealResolver: Sendable {
    /// Which rung produced the answer — surfaced by LookupLab (the CQ1 spike metric) and
    /// useful in logs; the product UI shows provenance, not rungs.
    public enum Rung: String, Sendable, Hashable {
        case userStated
        case printedLabel
        case barcodeDatabase
        case searchExcerpts
        case agenticLookup
        case estimate
    }

    private let barcodeDB: (any BarcodeNutritionDatabase)?
    private let searcher: (any NutritionWebSearcher)?
    private let adjudicator: (any ExcerptAdjudicator)?
    private let agent: (any AgenticLookup)?
    private let estimator: any PlateEstimator

    public init(
        barcodeDB: (any BarcodeNutritionDatabase)?,
        searcher: (any NutritionWebSearcher)?,
        adjudicator: (any ExcerptAdjudicator)?,
        agent: (any AgenticLookup)?,
        estimator: any PlateEstimator
    ) {
        self.barcodeDB = barcodeDB
        self.searcher = searcher
        self.adjudicator = adjudicator
        self.agent = agent
        self.estimator = estimator
    }

    /// Walks the rungs in cost order and returns the first success. Rung errors are treated
    /// as fall-through, not failure — a network blip on one rung must not cost the user the
    /// cheaper answer below it.
    public func resolve(
        item: DraftItem,
        seller: Seller?,
        capture: MealCapture?,
        answers: [QuestionAnswer]
    ) async -> (nutrition: ResolvedNutrition, rung: Rung) {
        // wantAlternates: false — everyday lookups keep the lean single-answer model call;
        // the heavier multi-candidate schema runs only when the user asked for options.
        let result = await core(item: item, seller: seller, capture: capture,
                                answers: answers, wantAlternates: false)
        return (result.nutrition, result.rung)
    }

    /// `resolve` plus the other defensible matches the search rung saw (P6 refresh — "not
    /// this one? pick the next best"). Alternates exist only when the adjudicator is
    /// candidate-capable AND the answer came from the search rung; every other rung has
    /// exactly one honest answer (the user's number, the printed label, the barcode product,
    /// the estimate) and returns none. Alternates are transient — recomputed per lookup,
    /// never persisted.
    public func resolveWithAlternates(
        item: DraftItem,
        seller: Seller?,
        capture: MealCapture?,
        answers: [QuestionAnswer]
    ) async -> (nutrition: ResolvedNutrition, alternates: [ResolvedAlternative], rung: Rung) {
        await core(item: item, seller: seller, capture: capture, answers: answers, wantAlternates: true)
    }

    private func core(
        item: DraftItem,
        seller: Seller?,
        capture: MealCapture?,
        answers: [QuestionAnswer],
        wantAlternates: Bool
    ) async -> (nutrition: ResolvedNutrition, alternates: [ResolvedAlternative], rung: Rung) {
        // The user stated the number ("…, 400 calories") — their number wins over everything,
        // including a printed label (build 8: the whole point of stating it).
        if let statedFacts = item.statedFacts {
            return (ResolvedNutrition(facts: statedFacts, provenance: .userStated), [], .userStated)
        }

        // A parsed label is the seller's own printed data — nothing to look up.
        if let labelFacts = item.labelFacts {
            return (ResolvedNutrition(facts: labelFacts, provenance: .verified(sourceURL: nil)), [], .printedLabel)
        }

        if let barcode = item.barcode, let barcodeDB {
            if let hit = try? await barcodeDB.lookup(barcode: barcode) {
                return (hit, [], .barcodeDatabase)
            }
        }

        if let searcher, let adjudicator {
            let objective = MealPromptBuilder.searchObjective(item: item, seller: seller)
            let queries = MealPromptBuilder.searchQueries(item: item, seller: seller)
            if let excerpts = try? await searcher.search(objective: objective, queries: queries),
               !excerpts.isEmpty {
                if wantAlternates,
                   let candidateCapable = adjudicator as? any CandidateAdjudicator,
                   let candidates = try? await candidateCapable.adjudicateCandidates(
                       item: item, seller: seller, excerpts: excerpts),
                   let best = candidates.first {
                    return (best.nutrition, Self.dedupedAlternates(candidates), .searchExcerpts)
                }
                if let judged = try? await adjudicator.adjudicate(item: item, seller: seller, excerpts: excerpts) {
                    return (judged, [], .searchExcerpts)
                }
            }
        }

        if let agent, let found = try? await agent.research(item: item, seller: seller) {
            return (found, [], .agenticLookup)
        }

        // Bottom rung: always answers. If even the estimator throws (it shouldn't — the
        // scripted and production estimators are total), degrade to an explicitly unknown
        // wide range rather than propagating an error into the log flow.
        if let estimate = try? await estimator.estimate(item: item, capture: capture, answers: answers) {
            return (estimate, [], .estimate)
        }
        let unknown = ResolvedNutrition(
            facts: NutritionFacts(energy: .range(lowKcal: 100, highKcal: 800)),
            provenance: .estimate(assumptions: ["Could not identify this item — very rough range"])
        )
        return (unknown, [], .estimate)
    }

    /// The pickable list behind the primary: drop the primary itself and any junk duplicate
    /// (same name + same midpoint kcal — small models repeat themselves), cap at 3.
    static func dedupedAlternates(_ candidates: [ResolvedAlternative]) -> [ResolvedAlternative] {
        guard candidates.count > 1 else { return [] }
        var seen: Set<String> = []
        if let best = candidates.first {
            seen.insert(key(best))
        }
        var kept: [ResolvedAlternative] = []
        for candidate in candidates.dropFirst() {
            let candidateKey = key(candidate)
            guard !seen.contains(candidateKey) else { continue }
            seen.insert(candidateKey)
            kept.append(candidate)
            if kept.count == 3 { break }
        }
        return kept
    }

    private static func key(_ candidate: ResolvedAlternative) -> String {
        "\(candidate.name.lowercased())|\(Int(candidate.nutrition.facts.energy.midpointKcal.rounded()))"
    }
}
