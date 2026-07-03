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

    private let pipeline: any MealPipeline
    private let resolver: MealResolver
    private let recorder: any NutritionRecorder
    private let queue: PendingMealQueue?
    private var capture: MealCapture?
    private var answers: [DraftItem.ID: QuestionAnswer] = [:]
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
        phase = .identifying

        do {
            let draft = try await pipeline.identify(capture)
            guard token == generation else { return }
            if draft.items.isEmpty {
                self.error = "Couldn't find any food in that capture. Try again closer, or with better light."
                phase = .idle
                return
            }
            self.draft = draft
            phase = .confirming
        } catch {
            guard token == generation else { return }
            self.error = "Couldn't read that capture. Try again."
            phase = .idle
        }
    }

    /// Sheet dismissed / user cancelled — abandon everything in flight.
    public func cancel() {
        generation += 1
        draft = nil
        capture = nil
        answers = [:]
        error = nil
        phase = .idle
    }

    // MARK: - Confirmation-screen edits

    public func toggleItem(_ id: DraftItem.ID) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].isChecked.toggle()
        self.draft = draft
    }

    public func editItemName(_ id: DraftItem.ID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var draft,
              let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].name = trimmed
        self.draft = draft
    }

    public func setQuantity(_ id: DraftItem.ID, quantity: Int) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].quantity = max(1, min(quantity, 20))
        self.draft = draft
    }

    public func answer(_ answer: QuestionAnswer, itemID: DraftItem.ID) {
        answers[itemID] = answer
    }

    // MARK: - Commit (the Log tap)

    /// Records every checked item. Returns immediately in spirit — the phase flips to
    /// `.logging` and the caller dismisses the sheet; the per-item ladder runs on.
    public func commit() async {
        guard let draft, phase == .confirming else { return }
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

        phase = .logging
        itemStatuses = checked.map { ItemStatus(id: $0.id, name: $0.name, state: .waiting) }

        // Sequential fan-out: PCC-rate-friendly, and per-item statuses keep it honest. Each
        // item is queued before its lookup so an app quit mid-ladder resumes next launch.
        for item in checked {
            guard token == generation else { return }
            let itemAnswers = answers[item.id].map { [$0] } ?? defaultAnswers(for: item)
            setStatus(item.id, .lookingUp)

            let pendingID = UUID()
            queue?.enqueue(PendingMealQueue.PendingItem(
                id: pendingID,
                date: Date(),
                item: PendingMealQueue.PendingDraft(from: item),
                seller: draft.seller,
                answers: itemAnswers
            ))

            let (resolved, _) = await resolver.resolve(
                item: item,
                seller: draft.seller,
                capture: capture,
                answers: itemAnswers
            )
            guard token == generation else { return }

            let entry = MealEntry(
                date: Date(),
                name: item.name,
                quantity: item.quantity,
                facts: resolved.facts,
                provenance: resolved.provenance
            )
            do {
                try await recorder.record(entry)
                queue?.remove(id: pendingID)
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
                provenance: resolved.provenance
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
        return [QuestionAnswer(questionID: question.id, optionID: fallback.id)]
    }

    private func setStatus(_ id: DraftItem.ID, _ state: ItemStatus.State) {
        guard let index = itemStatuses.firstIndex(where: { $0.id == id }) else { return }
        itemStatuses[index].state = state
    }
}
