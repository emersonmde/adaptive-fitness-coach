import Foundation

/// The P4 seam — the `CoachEngine` pattern for the meal pipeline, deliberately a *sibling*
/// protocol rather than a `CoachSession`: stages in, structured results out, no conversation,
/// no streams (spec §5). Production is FoundationModels (phone target); the deterministic
/// `ScriptedMealPipeline` backs `-simulateMealScan` and the unit tests.
///
/// Stage boundaries follow the spec's staged-pipeline discipline:
/// - `identify` = stages 1–3 (classify → seller → item list). Fast, drives the confirm screen.
/// - `resolve`  = stage 4, one call per *confirmed* item, each an independent context (§5
///   context discipline — the item list is the state, nothing survives between items).
/// - `estimate` = stage 5, the honest fallback (plate photos, unresolvable items).
public enum MealPipelineAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public protocol MealPipeline: Sendable {
    var availability: MealPipelineAvailability { get }

    /// Stages 1–3: classify the capture, identify the seller, extract the item list.
    /// Implementations must resolve barcodes/labels deterministically before any model call.
    func identify(_ capture: MealCapture) async throws -> MealDraft

    /// Stage 4: look up one confirmed item's real nutrition (retrieval before estimation, C2).
    /// Fresh context per item. Runs only after the user commits (§5 — never spend lookups on
    /// unchecked items).
    func resolve(item: DraftItem, seller: Seller?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition

    /// Stage 5: the labeled-estimate fallback. Must return a range with stated assumptions;
    /// `Provenance.estimate` is the only acceptable grade here (C3).
    func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition
}
