import Foundation
import Observation

/// The meal-logging flow's state machine — `CoachConversation` for the capture loop. Owns
/// capture → identify → confirm → commit → per-item finalize, engine-agnostic and clock-free,
/// so the whole flow is unit-tested against `ScriptedMealPipeline` + `InMemoryNutritionRecorder`
/// and driven identically by the real UI.
///
/// The optimistic contract (DESIGN-PRINCIPLES 11 / spec §4.4): `commit()` returns the user to
/// their day immediately; lookups run sequentially behind the scenes; each item's status is
/// honest ("Looking up…" → "Saved") and "Saved" appears only after the recorder confirms (N6).
@MainActor
@Observable
public final class MealLogController {

    public enum Phase: Equatable {
        case idle
        case identifying
        case confirming
        /// Identify failed (or found nothing) — the flow sheet stays up and shows `error`
        /// with a retry, instead of silently dropping the user back where they were.
        case failed
        /// Post-commit: lookups/writes may still be running; the daily line shows statuses.
        case logging
        case done
    }

    public struct ItemStatus: Identifiable, Sendable {
        public enum State: Sendable, Equatable {
            case waiting
            case lookingUp
            case saved(MealEntry)
            /// Honest failure with an exit (principle 13): the item can be retried or dropped.
            case failed(String)
        }
        public let id: DraftItem.ID
        public var name: String
        public var state: State
    }

    public private(set) var phase: Phase = .idle
    public private(set) var draft: MealDraft?
    public private(set) var itemStatuses: [ItemStatus] = []
    /// Honest, user-facing error for identify/auth failures (retryable; never a dead end).
    public private(set) var error: String?
    /// Pre-commit lookups (build 10): resolved while the confirmation screen is open so the
    /// user sees the number (and its source) *before* Log, and can override it. Keyed by
    /// item; a missing key with the item checked means "Looking up…".
    public private(set) var resolutions: [DraftItem.ID: ResolvedNutrition] = [:]

    // The when-row's state (build 8): when the entries happened and which meal they belong
    // to. Prefilled from the capture (receipt's printed date, a typed "yesterday"), always
    // user-editable on the confirmation screen.
    public private(set) var loggedDate = Date()
    public private(set) var mealSlot: MealSlot = .snack
    /// True when `loggedDate` came from the capture itself (receipt date / typed phrase) —
    /// the when-row labels it honestly ("From receipt").
    public private(set) var prefilledFromCapture = false
    private var slotWasManuallyChosen = false

    private let pipeline: any MealPipeline
    private let resolver: MealResolver
    private let recorder: any NutritionRecorder
    private let queue: PendingMealQueue?
    private var capture: MealCapture?
    private var answers: [DraftItem.ID: QuestionAnswer] = [:]
    /// Pre-resolve bookkeeping: the active drain (callers chain onto it, so lookups stay
    /// strictly sequential — PCC-rate-friendly — and every caller's await means "fully
    /// drained"), plus a per-item epoch so an edit/answer that invalidates a lookup
    /// mid-flight discards the stale result instead of storing it.
    private var activeResolveLoop: Task<Void, Never>?
    private var resolutionEpochs: [DraftItem.ID: Int] = [:]
    private var isCommitting = false
    /// Turn-token guard (CoachConversation pattern): a stale identify/commit finishing late
    /// can't corrupt a newer session's state.
    private var generation = 0

    public init(
        pipeline: any MealPipeline,
        resolver: MealResolver,
        recorder: any NutritionRecorder,
        queue: PendingMealQueue? = nil
    ) {
        self.pipeline = pipeline
        self.resolver = resolver
        self.recorder = recorder
        self.queue = queue
    }

    // MARK: - Capture → confirm

    public func beginCapture(_ capture: MealCapture) async {
        generation += 1
        let token = generation
        self.capture = capture
        answers = [:]
        error = nil
        resolutions = [:]
        resolutionEpochs = [:]
        itemStatuses = []   // a previous session's Saved/Failed rows must not bleed through
        phase = .identifying

        do {
            let draft = try await pipeline.identify(capture)
            guard token == generation else { return }
            if draft.items.isEmpty {
                self.error = "Couldn't find any food in that capture. Try again closer, or with better light."
                phase = .failed
                return
            }
            self.draft = draft
            // Same clamp as setLoggedDate: a hallucinated/misread capture date must not
            // record a meal into the future (ReceiptDateParser clamps, the model may not).
            loggedDate = min(draft.capturedAt ?? Date(), Date())
            prefilledFromCapture = draft.capturedAt != nil
            slotWasManuallyChosen = false
            mealSlot = draft.suggestedSlot ?? MealSlot.suggested(for: loggedDate)
            phase = .confirming
            // Start looking up checked items right away — the confirmation screen shows
            // each number (and its source) as it lands, before the user commits.
            Task { await self.resolveOutstandingItems() }
        } catch {
            guard token == generation else { return }
            self.error = "Couldn't read that capture. Try again."
            phase = .failed
        }
    }

    /// Re-run identify on the capture that just failed (a model/network blip is transient).
    public func retryCapture() async {
        guard phase == .failed, let capture else {
            cancel()
            return
        }
        await beginCapture(capture)
    }

    /// Sheet dismissed / user cancelled — abandon everything in flight.
    public func cancel() {
        generation += 1
        draft = nil
        capture = nil
        answers = [:]
        error = nil
        resolutions = [:]
        resolutionEpochs = [:]
        itemStatuses = []
        phase = .idle
    }

    // MARK: - Confirmation-screen edits

    public func toggleItem(_ id: DraftItem.ID) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].isChecked.toggle()
        self.draft = draft
        // Checking an item it never looked up starts its lookup (unchecked items never
        // spend one — §5's rule survives, applied to the checked set as it stands now).
        if draft.items[index].isChecked {
            Task { await self.resolveOutstandingItems() }
        }
    }

    public func editItemName(_ id: DraftItem.ID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var draft,
              let index = draft.items.firstIndex(where: { $0.id == id }),
              draft.items[index].name != trimmed else { return }
        draft.items[index].name = trimmed
        // A stated override keeps its energy (the user's number was for the food they
        // meant), but macros inherited from the OLD name's lookup no longer apply.
        if let stated = draft.items[index].statedFacts {
            draft.items[index].statedFacts = NutritionFacts(energy: stated.energy)
        }
        self.draft = draft
        invalidateResolution(id)   // the name is the lookup key — a rename re-resolves
    }

    public func setQuantity(_ id: DraftItem.ID, quantity: Int) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].quantity = max(1, min(quantity, 20))
        self.draft = draft
        // Quantity multiplies at record time — the per-serving resolution stays valid.
    }

    public func answer(_ answer: QuestionAnswer, itemID: DraftItem.ID) {
        answers[itemID] = answer
        invalidateResolution(itemID)   // the answer feeds the estimate — re-resolve
    }

    /// The user's own calorie number, set on the confirmation screen. Becomes `statedFacts`
    /// (→ `.userStated`, the ladder's top rung), keeping any looked-up macros — the user
    /// restated energy, not composition (same semantics as the post-hoc edit).
    public func setCalories(_ id: DraftItem.ID, kcal: Double) {
        guard kcal > 0, var draft,
              let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        var facts = draft.items[index].statedFacts
            ?? resolutions[id]?.facts
            ?? NutritionFacts(energy: .exact(kcal: kcal))
        facts.energy = .exact(kcal: kcal)
        draft.items[index].statedFacts = facts
        self.draft = draft
    }

    /// What the confirmation screen shows for an item right now: the user's stated number
    /// first, then the finished lookup, else nil ("Looking up…").
    public func displayedNutrition(for id: DraftItem.ID) -> ResolvedNutrition? {
        if let stated = draft?.items.first(where: { $0.id == id })?.statedFacts {
            return ResolvedNutrition(facts: stated, provenance: .userStated)
        }
        return resolutions[id]
    }

    // MARK: - Pre-commit lookups (build 10)

    /// Resolves every checked item that has no number yet. Every caller chains onto the
    /// active drain, so lookups stay strictly sequential across all triggers (beginCapture,
    /// re-checks, invalidations — PCC-rate-friendly), and awaiting this method always means
    /// "everything unresolved at call time is drained". A mid-flight invalidation discards
    /// the stale result via its epoch and the item re-resolves before the drain ends.
    public func resolveOutstandingItems() async {
        let previous = activeResolveLoop
        let task = Task {
            await previous?.value
            await self.drainUnresolvedItems()
        }
        activeResolveLoop = task
        await task.value
        if activeResolveLoop == task { activeResolveLoop = nil }
    }

    private func drainUnresolvedItems() async {
        let token = generation
        while phase == .confirming, token == generation, let item = nextUnresolvedItem() {
            let epoch = resolutionEpochs[item.id, default: 0]
            let itemAnswers = answers[item.id].map { [$0] } ?? defaultAnswers(for: item)
            let (resolved, _) = await resolver.resolve(
                item: item,
                seller: draft?.seller,
                capture: capture,
                answers: itemAnswers
            )
            guard token == generation, phase == .confirming else { return }
            if resolutionEpochs[item.id, default: 0] == epoch {
                resolutions[item.id] = resolved
            }
            // else: invalidated mid-flight — the while re-picks the item and resolves fresh.
        }
    }

    private func nextUnresolvedItem() -> DraftItem? {
        draft?.items.first {
            $0.isChecked && $0.statedFacts == nil && resolutions[$0.id] == nil
        }
    }

    private func invalidateResolution(_ id: DraftItem.ID) {
        resolutionEpochs[id, default: 0] += 1
        resolutions[id] = nil
        Task { await self.resolveOutstandingItems() }
    }

    // MARK: - The when-row (build 8)

    public func setMealSlot(_ slot: MealSlot) {
        mealSlot = slot
        slotWasManuallyChosen = true
    }

    /// Changing the day re-suggests the slot from the new time — unless the user already
    /// picked one (their choice outranks the heuristic).
    public func setLoggedDate(_ date: Date) {
        loggedDate = min(date, Date())   // meals aren't logged into the future
        if !slotWasManuallyChosen {
            mealSlot = MealSlot.suggested(for: loggedDate)
        }
    }

    // MARK: - Commit (the Log tap)

    /// Records every checked item. Returns immediately in spirit — the phase flips to
    /// `.logging` and the caller dismisses the sheet; the per-item ladder runs on.
    public func commit() async {
        // `isCommitting` closes the re-entrancy window the phase check alone leaves open:
        // phase flips to .logging only after the auth await, so a double-tap of Log would
        // otherwise run two full record loops (every meal in Health twice).
        guard let draft, phase == .confirming, !isCommitting else { return }
        isCommitting = true
        defer { isCommitting = false }
        let token = generation
        let checked = draft.items.filter(\.isChecked)
        guard !checked.isEmpty else {
            cancel()
            return
        }

        // Deferred-contextual authorization: the value of granting is maximally clear right
        // now. A failure here is honest and blocking — never a fake "Saved".
        do {
            try await recorder.requestAuthorization()
        } catch {
            guard token == generation else { return }
            self.error = "Health access is off — meals can't be saved. Enable it in Settings › Health."
            return
        }
        guard token == generation else { return }
        error = nil   // a previous attempt's auth error is history once this one proceeds

        phase = .logging
        itemStatuses = checked.map { ItemStatus(id: $0.id, name: $0.name, state: .waiting) }

        // The Log tap is the durability point: EVERY checked item is queued before the
        // first lookup/write, so an app quit anywhere mid-commit resumes the whole set at
        // next launch — not just the items the loop had reached. (record → remove leaves a
        // tiny at-least-once window; for food logging a rare duplicate beats a lost meal.)
        var pendingIDs: [DraftItem.ID: UUID] = [:]
        for item in checked {
            let pendingID = UUID()
            pendingIDs[item.id] = pendingID
            queue?.enqueue(PendingMealQueue.PendingItem(
                id: pendingID,
                date: loggedDate,
                item: PendingMealQueue.PendingDraft(from: item),
                seller: draft.seller,
                answers: answers[item.id].map { [$0] } ?? defaultAnswers(for: item),
                meal: mealSlot
            ))
        }

        // Sequential fan-out: PCC-rate-friendly, and per-item statuses keep it honest.
        for item in checked {
            guard token == generation else { return }
            let itemAnswers = answers[item.id].map { [$0] } ?? defaultAnswers(for: item)
            setStatus(item.id, .lookingUp)

            // The number the user saw is the number that records: the confirmation screen's
            // finished lookup (or their stated override, which the resolver honors first) is
            // reused; only an item still mid-lookup at Log time resolves here.
            let resolved: ResolvedNutrition
            if item.statedFacts == nil, let cached = resolutions[item.id] {
                resolved = cached
            } else {
                resolved = await resolver.resolve(
                    item: item,
                    seller: draft.seller,
                    capture: capture,
                    answers: itemAnswers
                ).nutrition
            }
            guard token == generation else { return }

            let entry = MealEntry(
                date: loggedDate,
                name: item.name,
                quantity: item.quantity,
                facts: resolved.facts,
                provenance: resolved.provenance,
                meal: mealSlot,
                seller: draft.seller
            )
            do {
                try await recorder.record(entry)
                if let pendingID = pendingIDs[item.id] {
                    queue?.remove(id: pendingID)
                }
                guard token == generation else { return }
                setStatus(item.id, .saved(entry))
            } catch {
                guard token == generation else { return }
                // The pending row stays — the write retries on next launch's drain.
                setStatus(item.id, .failed("Couldn't save to Health"))
            }
        }
        guard token == generation else { return }
        phase = .done
        self.draft = nil
    }

    /// Launch-time drain: finish anything that was mid-flight when the app last quit.
    public func resumePending() async {
        guard let queue else { return }
        let token = generation
        for pending in queue.pending {
            guard token == generation else { return }
            let item = pending.item.draftItem
            let (resolved, _) = await resolver.resolve(
                item: item,
                seller: pending.seller,
                capture: nil,
                answers: pending.answers
            )
            let entry = MealEntry(
                date: pending.date,
                name: item.name,
                quantity: item.quantity,
                facts: resolved.facts,
                provenance: resolved.provenance,
                meal: pending.meal,   // nil (build-8 rows) → init derives from the date
                seller: pending.seller
            )
            if (try? await recorder.record(entry)) != nil {
                queue.remove(id: pending.id)
            }
        }
    }

    // MARK: -

    /// C1: untouched questions answer themselves with their default — skipping is free.
    private func defaultAnswers(for item: DraftItem) -> [QuestionAnswer] {
        guard let question = item.question, let fallback = question.defaultOption else { return [] }
        return [QuestionAnswer(question: question, option: fallback)]
    }

    private func setStatus(_ id: DraftItem.ID, _ state: ItemStatus.State) {
        guard let index = itemStatuses.firstIndex(where: { $0.id == id }) else { return }
        itemStatuses[index].state = state
    }
}
