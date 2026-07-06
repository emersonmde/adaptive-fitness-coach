import Foundation

/// The phone-side brain of the watch quick-log (P6). Since the always-pending rework
/// (2026-07), `enqueueForReview` is the primary path: every watch log parks as a
/// pending-REVIEW row, looked up when the user opens the review card.
///
/// `draft`/`commit` serve the RETIRED live channel — build-≤17 watches still round-trip
/// through them (identify → resolve into a compact draft, held so confirm commits EXACTLY
/// what the wrist showed). Delete alongside `QuickLogCoordinator.handleLive` once
/// always-pending watches are the installed floor.
///
/// Deliberately separate from `MealLogController`: the controller's phases drive the phone's
/// own confirmation UI (its `.confirming` state presents a sheet), and a watch-originated
/// log must never pop UI on the phone. Same seams (`MealPipeline`/`MealResolver`/
/// `NutritionRecorder`/`PendingMealQueue`), so the scripted pipeline drives it in tests.
@MainActor
public final class QuickLogService {
    private let pipeline: any MealPipeline
    private let resolver: MealResolver
    private let recorder: any NutritionRecorder
    private let queue: PendingMealQueue?

    /// What `draft(for:)` resolved, held so `commit` records the numbers the watch showed.
    private struct PreparedMeal {
        var request: QuickLogRequest
        var items: [DraftItem]
        var resolutions: [DraftItem.ID: ResolvedNutrition]
        var seller: Seller?
        var slot: MealSlot
    }

    private var prepared: [UUID: PreparedMeal] = [:]

    public init(
        pipeline: any MealPipeline,
        resolver: MealResolver,
        recorder: any NutritionRecorder,
        queue: PendingMealQueue?
    ) {
        self.pipeline = pipeline
        self.resolver = resolver
        self.recorder = recorder
        self.queue = queue
    }

    /// Identify + resolve the dictated text and return the compact draft, or nil when the
    /// pipeline is unavailable/failed — the watch then falls back to the offline queue path
    /// (honest "will look it up when your iPhone is nearby", never a made-up number).
    public func draft(for request: QuickLogRequest) async -> QuickLogDraft? {
        guard case .available = pipeline.availability else { return nil }
        guard let mealDraft = try? await pipeline.identify(MealCapture(typedText: request.text)) else {
            return nil
        }
        let items = mealDraft.items.filter(\.isChecked)
        guard !items.isEmpty else { return nil }

        var resolutions: [DraftItem.ID: ResolvedNutrition] = [:]
        for item in items {
            let answers = defaultAnswers(for: item)
            resolutions[item.id] = await resolver.resolve(
                item: item, seller: mealDraft.seller, capture: nil, answers: answers
            ).nutrition
        }

        let slot = mealDraft.suggestedSlot ?? MealSlot.suggested(for: request.date)
        prepared[request.id] = PreparedMeal(
            request: request, items: items, resolutions: resolutions,
            seller: mealDraft.seller, slot: slot
        )

        let perItem = items.compactMap { item in
            resolutions[item.id].map { (item: item, nutrition: $0) }
        }
        let total = perItem.reduce(0.0) {
            $0 + $1.nutrition.facts.energy.midpointKcal * Double(max(1, $1.item.quantity))
        }
        let isEstimate = perItem.contains { $0.nutrition.facts.energy.isRange }
        let source: String
        if perItem.count == 1, let only = perItem.first {
            source = only.nutrition.provenance.detailLabel
        } else {
            source = "\(perItem.count) items"
        }
        return QuickLogDraft(
            requestId: request.id,
            name: items.map(\.name).joined(separator: ", "),
            itemCount: items.count,
            totalKcal: Int(total.rounded()),
            isEstimate: isEstimate,
            sourceLabel: source
        )
    }

    /// Commit (or discard) a prepared draft. Mirrors `MealLogController.commit`'s durability
    /// contract: every item is queued before the first write, rows are removed only on a
    /// confirmed write, and `saved` is true only when every write confirmed (N6).
    public func commit(_ confirm: QuickLogConfirm) async -> QuickLogOutcome {
        guard let meal = prepared.removeValue(forKey: confirm.requestId) else {
            return QuickLogOutcome(requestId: confirm.requestId, saved: false)
        }
        guard confirm.accept else {
            return QuickLogOutcome(requestId: confirm.requestId, saved: false)
        }
        guard (try? await recorder.requestAuthorization()) != nil else {
            return QuickLogOutcome(requestId: confirm.requestId, saved: false)
        }

        var pendingIDs: [DraftItem.ID: UUID] = [:]
        for item in meal.items {
            let pendingID = UUID()
            pendingIDs[item.id] = pendingID
            queue?.enqueue(PendingMealQueue.PendingItem(
                id: pendingID,
                date: meal.request.date,
                item: PendingMealQueue.PendingDraft(from: item),
                seller: meal.seller,
                answers: defaultAnswers(for: item),
                meal: meal.slot
            ))
        }

        var allSaved = true
        for item in meal.items {
            guard let resolved = meal.resolutions[item.id] else { allSaved = false; continue }
            let entry = MealEntry(
                date: meal.request.date,
                name: item.name,
                quantity: item.quantity,
                facts: resolved.facts,
                provenance: resolved.provenance,
                meal: meal.slot,
                seller: meal.seller
            )
            if (try? await recorder.record(entry)) != nil {
                if let pendingID = pendingIDs[item.id] { queue?.remove(id: pendingID) }
            } else {
                allSaved = false   // the pending row stays; next launch's drain retries
            }
        }
        return QuickLogOutcome(requestId: confirm.requestId, saved: allSaved)
    }

    /// Offline path: park the raw text as a REVIEW row — surfaced with a badge, committed
    /// only through the normal confirmation sheet, skipped by the drain.
    public func enqueueForReview(_ request: QuickLogRequest) {
        queue?.enqueue(PendingMealQueue.PendingItem(
            date: request.date,
            item: PendingMealQueue.PendingDraft(name: request.text, quantity: 1),
            seller: nil,
            answers: [],
            needsReview: true,
            sourceText: request.text
        ))
    }

    private func defaultAnswers(for item: DraftItem) -> [QuestionAnswer] {
        guard let question = item.question, let fallback = question.defaultOption else { return [] }
        return [QuestionAnswer(question: question, option: fallback)]
    }
}
