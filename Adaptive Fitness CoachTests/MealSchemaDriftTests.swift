import Foundation
import Testing
import FoundationModels
import AdaptiveCore
@testable import Adaptive_Fitness_Coach

/// Pins the P4 `@Generable` meal mirrors to their package models (the CoachSchemaDriftTests
/// pattern): every mirror funnels through exactly one `toPackage()`, and the C3 invariants —
/// estimates are ALWAYS ranges, unfound lookups are ALWAYS nil — hold at the funnel, so a
/// drifted field or guide fails here before a live model ever sees it.
struct MealSchemaDriftTests {

    @Test func draftMirrorFunnelsToPackage() {
        let mirror = GenerableMealDraft(
            sellerName: "Trader Joe's",
            sellerDomain: "TraderJoes.com",
            items: [
                GenerableDraftItem(name: "Chicken Caesar Salad", quantity: 1, eatingNow: true),
                GenerableDraftItem(name: "Penne Pasta (box)", quantity: 2, eatingNow: false),
                GenerableDraftItem(
                    name: "Rotisserie Chicken",
                    question: GenerableQuestion(prompt: "How much?", options: ["Quarter", "Half", "Whole"], defaultIndex: 1)
                ),
            ]
        )
        let draft = mirror.toPackage(classification: .receipt)
        #expect(draft.seller?.name == "Trader Joe's")
        #expect(draft.seller?.domainHint == "traderjoes.com")   // normalized lowercase
        #expect(draft.items.count == 3)
        #expect(draft.items[0].isChecked)
        #expect(!draft.items[1].isChecked)                      // pantry pre-unchecked (§4.3)
        #expect(draft.items[1].quantity == 2)
        let question = draft.items[2].question
        #expect(question?.options.count == 3)
        #expect(question?.defaultOption?.label == "Half")
    }

    @Test func questionWithBadDefaultIndexStillSafe() {
        let question = GenerableQuestion(prompt: "Size?", options: ["Small", "Large"], defaultIndex: 3)
        let converted = question.toPackage(id: "q")
        #expect(converted?.defaultOption?.label == "Small")     // clamped, never crashes
    }

    @Test func lookupResultHonestyGates() {
        // found=false is nil no matter what else is set — the model can't leak a guess (C2).
        let refused = GenerableLookupResult(found: false, kcal: 480, sourceURL: "https://x.example")
        #expect(refused.toPackage(seller: nil) == nil)
        // found without a positive kcal is equally unusable.
        let hollow = GenerableLookupResult(found: true, kcal: 0)
        #expect(hollow.toPackage(seller: nil) == nil)
    }

    @Test func lookupResultGradesThroughProvenanceGrader() throws {
        let seller = Seller(name: "Wendy's", domainHint: "wendys.com")
        let verified = GenerableLookupResult(found: true, kcal: 460, sourceURL: "https://www.wendys.com/nutrition")
        let resolved = try #require(verified.toPackage(seller: seller))
        guard case .verified = resolved.provenance else {
            Issue.record("seller-domain source must grade verified"); return
        }
        let aggregator = GenerableLookupResult(found: true, kcal: 460, sourceURL: "https://menuwithnutrition.com/x")
        guard case .database = try #require(aggregator.toPackage(seller: seller)).provenance else {
            Issue.record("aggregator must grade database"); return
        }
    }

    @Test func lookupCandidatesFunnelDropsHollowRowsAndKeepsOrder() throws {
        // P6 refresh/alternates mirror: order is the contract (first = best), zero-kcal rows
        // drop at the funnel, and provenance grades per candidate through the same grader.
        let seller = Seller(name: "Wendy's", domainHint: "wendys.com")
        let mirror = GenerableLookupCandidates(candidates: [
            GenerableLookupCandidate(name: "Dave's Single", kcal: 590,
                                     sourceURL: "https://www.wendys.com/nutrition"),
            GenerableLookupCandidate(name: "Phantom", kcal: 0),
            GenerableLookupCandidate(name: "Dave's Double", kcal: 810,
                                     sourceURL: "https://menuwithnutrition.com/x"),
        ])
        let converted = mirror.toPackage(seller: seller)
        #expect(converted.map(\.name) == ["Dave's Single", "Dave's Double"])
        guard case .verified = try #require(converted.first).nutrition.provenance else {
            Issue.record("seller-domain candidate must grade verified"); return
        }
        guard case .database = try #require(converted.last).nutrition.provenance else {
            Issue.record("aggregator candidate must grade database"); return
        }
    }

    @Test func estimateIsAlwaysARange() {
        // C3's binding invariant, enforced at the funnel even when the model misbehaves.
        let inverted = GenerableEstimate(lowKcal: 700, highKcal: 500, assumptions: ["Bowl"])
        let resolved = inverted.toPackage()
        #expect(resolved.facts.energy.isRange)
        guard case .range(let low, let high) = resolved.facts.energy else { return }
        #expect(low < high)
        guard case .estimate = resolved.provenance else {
            Issue.record("estimator output must grade estimate"); return
        }

        let degenerate = GenerableEstimate(lowKcal: 500, highKcal: 500, assumptions: ["Plate"])
        guard case .range(let dLow, let dHigh) = degenerate.toPackage().facts.energy else {
            Issue.record("degenerate estimate must widen to a range"); return
        }
        #expect(dHigh > dLow)
    }

    @Test func generationSchemasBuild() {
        // Exercises every @Guide constraint (bad guides fail here, not in a live session) —
        // the CoachSchemaDriftTests.proposePlanToolSchemaBuilds pattern.
        _ = GenerableMealDraft.generationSchema
        _ = GenerableLookupResult.generationSchema
        _ = GenerableEstimate.generationSchema
        _ = WebSearchTool(searcher: ScriptedSearcher()).parameters
        _ = FetchPageTool().parameters
    }
}
