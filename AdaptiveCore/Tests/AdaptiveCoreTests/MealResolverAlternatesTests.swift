import Foundation
import Testing
@testable import AdaptiveCore

/// P6 refresh/alternates: the candidate path engages only when asked, dedupes junk, caps at
/// three, and every other rung stays single-answer.
struct MealResolverAlternatesTests {

    private final class SpyCandidateAdjudicator: CandidateAdjudicator, @unchecked Sendable {
        var candidates: [ResolvedAlternative] = []
        var singleAnswer: ResolvedNutrition?
        private(set) var candidateCalls = 0
        private(set) var singleCalls = 0

        func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
            singleCalls += 1
            return singleAnswer
        }

        func adjudicateCandidates(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> [ResolvedAlternative] {
            candidateCalls += 1
            return candidates
        }
    }

    private struct FixedEstimator: PlateEstimator {
        func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
            ResolvedNutrition(
                facts: NutritionFacts(energy: .range(lowKcal: 350, highKcal: 600)),
                provenance: .estimate(assumptions: [])
            )
        }
    }

    private func nutrition(_ kcal: Double) -> ResolvedNutrition {
        ResolvedNutrition(facts: NutritionFacts(energy: .exact(kcal: kcal)),
                          provenance: .database(name: "Open Food Facts", sourceURL: nil))
    }

    private func makeResolver(_ adjudicator: SpyCandidateAdjudicator) -> MealResolver {
        MealResolver(barcodeDB: nil, searcher: ScriptedSearcher(),
                     adjudicator: adjudicator, agent: nil, estimator: FixedEstimator())
    }

    @Test func alternatesComeBackDedupedAndCapped() async {
        let spy = SpyCandidateAdjudicator()
        spy.candidates = [
            ResolvedAlternative(name: "Cola 12 oz", nutrition: nutrition(140)),
            ResolvedAlternative(name: "Cola 12 oz", nutrition: nutrition(140)),   // dup of best
            ResolvedAlternative(name: "Cola 20 oz", nutrition: nutrition(240)),
            ResolvedAlternative(name: "Cola 20 oz", nutrition: nutrition(240)),   // dup alt
            ResolvedAlternative(name: "Cola Zero", nutrition: nutrition(0)),
            ResolvedAlternative(name: "Cherry Cola", nutrition: nutrition(150)),
            ResolvedAlternative(name: "Vanilla Cola", nutrition: nutrition(160)), // over the cap
        ]
        let result = await makeResolver(spy).resolveWithAlternates(
            item: DraftItem(name: "cola"), seller: nil, capture: nil, answers: [])

        #expect(result.nutrition == nutrition(140))
        #expect(result.rung == .searchExcerpts)
        #expect(result.alternates.map(\.name) == ["Cola 20 oz", "Cola Zero", "Cherry Cola"])
    }

    @Test func plainResolveNeverRunsTheCandidateCall() async {
        let spy = SpyCandidateAdjudicator()
        spy.singleAnswer = nutrition(140)
        spy.candidates = [ResolvedAlternative(name: "Cola", nutrition: nutrition(140))]
        let result = await makeResolver(spy).resolve(
            item: DraftItem(name: "cola"), seller: nil, capture: nil, answers: [])

        #expect(result.nutrition == nutrition(140))
        #expect(spy.candidateCalls == 0)   // everyday lookups stay on the lean single call
        #expect(spy.singleCalls == 1)
    }

    @Test func emptyCandidatesFallThroughToSingleThenEstimate() async {
        let spy = SpyCandidateAdjudicator()   // no candidates, no single answer
        let result = await makeResolver(spy).resolveWithAlternates(
            item: DraftItem(name: "mystery"), seller: nil, capture: nil, answers: [])

        #expect(spy.candidateCalls == 1)
        #expect(spy.singleCalls == 1)
        #expect(result.rung == .estimate)
        #expect(result.alternates.isEmpty)
    }

    @Test func statedNumberHasNoAlternates() async {
        let spy = SpyCandidateAdjudicator()
        spy.candidates = [ResolvedAlternative(name: "Cola", nutrition: nutrition(140))]
        let stated = DraftItem(name: "cola",
                               statedFacts: NutritionFacts(energy: .exact(kcal: 400)))
        let result = await makeResolver(spy).resolveWithAlternates(
            item: stated, seller: nil, capture: nil, answers: [])

        #expect(result.rung == .userStated)
        #expect(result.alternates.isEmpty)
        #expect(spy.candidateCalls == 0)
    }

    @Test func scriptedPipelineServesNameKeyedCandidatesForRescans() async {
        // The demo script's cola candidates, reached exactly the way the edit sheet does:
        // a fresh DraftItem (new id) built from the entry's name.
        let pipeline = ScriptedMealPipeline.demo()
        let resolver = pipeline.scriptedResolver()
        let result = await resolver.resolveWithAlternates(
            item: DraftItem(name: "Coca-Cola Classic 12 fl oz"),
            seller: nil, capture: nil, answers: [])

        #expect(result.rung == .searchExcerpts)
        #expect(Int(result.nutrition.facts.energy.midpointKcal) == 140)
        #expect(result.alternates.map(\.name) ==
                ["Coca-Cola Classic 20 fl oz", "Coca-Cola Zero Sugar 12 fl oz"])
    }
}
