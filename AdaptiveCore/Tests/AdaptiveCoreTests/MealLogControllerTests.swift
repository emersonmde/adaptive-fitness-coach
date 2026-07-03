import Foundation
import Testing
@testable import AdaptiveCore

/// The capture → confirm → commit flow, driven end-to-end on the scripted pipeline with the
/// in-memory recorder (the CoachConversationTests pattern: settle() polling, no clock).
@MainActor
struct MealLogControllerTests {

    private func makeController(
        pipeline: ScriptedMealPipeline = .demoGroceryReceipt(),
        recorder: InMemoryNutritionRecorder = InMemoryNutritionRecorder(),
        queue: PendingMealQueue? = nil
    ) -> (MealLogController, InMemoryNutritionRecorder) {
        let controller = MealLogController(
            pipeline: pipeline,
            resolver: pipeline.scriptedResolver(),
            recorder: recorder,
            queue: queue
        )
        return (controller, recorder)
    }

    private func tempQueue() -> PendingMealQueue {
        PendingMealQueue(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-test-\(UUID().uuidString).json"))
    }

    @Test func identifyMovesToConfirmingWithDraft() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["TRADER JOE'S", "CHKN CSR SLD"]))
        #expect(controller.phase == .confirming)
        #expect(controller.draft?.items.count == 4)
        #expect(controller.draft?.seller?.name == "Trader Joe's")
        // Pantry item arrives pre-unchecked (spec §4.3).
        #expect(controller.draft?.items.first { $0.id == ScriptedMealPipeline.DemoID.pasta }?.isChecked == false)
    }

    @Test func identifyFailureIsHonestAndRetryable() async {
        let draft = MealDraft(classification: .receipt, seller: nil, items: [DraftItem(name: "x")])
        let pipeline = ScriptedMealPipeline(script: .init(draft: draft, identifyError: URLError(.timedOut)))
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(MealCapture(ocrLines: ["blur"]))
        #expect(controller.phase == .idle)
        #expect(controller.error != nil)
        // Retry works: same controller, new capture on a working pipeline path is separate —
        // here we just confirm the controller isn't wedged.
        controller.cancel()
        #expect(controller.error == nil)
    }

    @Test func emptyDraftIsAnHonestMiss() async {
        let pipeline = ScriptedMealPipeline(script: .init(
            draft: MealDraft(classification: .unknown, seller: nil, items: [])
        ))
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(MealCapture())
        #expect(controller.phase == .idle)
        #expect(controller.error?.contains("Couldn't find") == true)
    }

    @Test func commitRecordsCheckedItemsOnly() async throws {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()

        #expect(controller.phase == .done)
        // 4 items, 1 pre-unchecked → 3 recorded.
        #expect(recorder.entries.count == 3)
        #expect(!recorder.entries.contains { $0.name.contains("Penne") })

        // Provenance flows through: salad is a database hit, curry an estimate range (C3).
        let salad = try #require(recorder.entries.first { $0.name.contains("Caesar") })
        #expect(salad.facts.energy == .exact(kcal: 460))
        guard case .database = salad.provenance else {
            Issue.record("salad should be a database hit"); return
        }
        let curry = try #require(recorder.entries.first { $0.name.contains("Curry") })
        #expect(curry.facts.energy.isRange)
        guard case .estimate = curry.provenance else {
            Issue.record("unresolvable item must grade estimate"); return
        }
    }

    @Test func statusesEndSavedAndHonest() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        #expect(controller.itemStatuses.count == 3)
        for status in controller.itemStatuses {
            guard case .saved = status.state else {
                Issue.record("\(status.name) did not end saved"); return
            }
        }
    }

    @Test func uncheckedToggleAndNameEditApply() async {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        controller.toggleItem(ScriptedMealPipeline.DemoID.salad)          // uncheck the salad
        controller.editItemName(ScriptedMealPipeline.DemoID.curry, name: "Lentil Curry (large)")
        await controller.commit()
        #expect(!recorder.entries.contains { $0.name.contains("Caesar") })
        #expect(recorder.entries.contains { $0.name == "Lentil Curry (large)" })
    }

    @Test func untouchedQuestionAnswersWithDefault() async {
        // The chicken has a portion question defaulting to "quarter" — committing without
        // touching it must not block or drop the item (C1: skippable by construction).
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        #expect(recorder.entries.contains { $0.name.contains("Rotisserie") })
    }

    @Test func deniedHealthAccessIsHonestBlockingState() async {
        let recorder = InMemoryNutritionRecorder()
        recorder.failAuthorization = true
        let (controller, _) = makeController(recorder: recorder)
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        #expect(controller.phase == .confirming)          // never a fake "Saved" (N6)
        #expect(controller.error?.contains("Health access") == true)
        #expect(recorder.entries.isEmpty)
    }

    @Test func failedWriteStaysPendingInQueue() async {
        let recorder = InMemoryNutritionRecorder()
        recorder.failWrites = true
        let queue = tempQueue()
        let (controller, _) = makeController(recorder: recorder, queue: queue)
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        // All three writes failed → all three rows still queued for the next-launch drain.
        #expect(queue.pending.count == 3)
        for status in controller.itemStatuses {
            guard case .failed = status.state else {
                Issue.record("\(status.name) should be honest about the failed save"); return
            }
        }
    }

    @Test func resumeDrainsThePendingQueue() async {
        let queue = tempQueue()
        queue.enqueue(PendingMealQueue.PendingItem(
            date: Date(),
            item: .init(name: "Chicken Caesar Salad", quantity: 1),
            seller: Seller(name: "Trader Joe's"),
            answers: []
        ))
        let (controller, recorder) = makeController(queue: queue)
        await controller.resumePending()
        #expect(queue.pending.isEmpty)
        #expect(recorder.entries.count == 1)
    }

    @Test func cancelDuringIdentifyDropsTheStaleResult() async {
        let pipeline = ScriptedMealPipeline.demoGroceryReceipt(delays: true)   // 600ms identify
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        let task = Task { await controller.beginCapture(MealCapture(ocrLines: ["receipt"])) }
        while controller.phase != .identifying { await Task.yield() }   // identify is in flight
        controller.cancel()                                // generation bump mid-identify
        await task.value
        #expect(controller.phase == .idle)                 // stale identify couldn't flip state
        #expect(controller.draft == nil)
    }

    @Test func successfulCommitLeavesQueueEmpty() async {
        let queue = tempQueue()
        let (controller, _) = makeController(queue: queue)
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        #expect(queue.pending.isEmpty)                     // C5: the queue is not a history
    }

    @Test func quantityMultipliesDailyTotalNotTheEntry() async throws {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        controller.setQuantity(ScriptedMealPipeline.DemoID.salad, quantity: 2)
        await controller.commit()
        let salad = try #require(recorder.entries.first { $0.name.contains("Caesar") })
        #expect(salad.quantity == 2)
        #expect(salad.facts.energy == .exact(kcal: 460))   // per-serving stays per-serving
        let intake = try await recorder.todayIntake()
        // 460×2 + 300 + estimate midpoint 475
        #expect(intake.totalKcal == 460 * 2 + 300 + 475)
    }
}
