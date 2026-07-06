import Foundation
import Testing
@testable import AdaptiveCore

// MARK: - Codec channel

struct QuickLogCodecTests {
    @Test func everyMessageShapeRoundTrips() throws {
        let request = QuickLogRequest(text: "chicken caesar salad from saladworks",
                                      date: Date(timeIntervalSince1970: 1_700_000_000))
        let draft = QuickLogDraft(requestId: request.id, name: "Chicken Caesar Salad",
                                  itemCount: 1, totalKcal: 460, isEstimate: false,
                                  sourceLabel: "verified · saladworks.com")
        let messages: [QuickLogMessage] = [
            .request(request),
            .draft(draft),
            .confirm(QuickLogConfirm(requestId: request.id, accept: true)),
            .outcome(QuickLogOutcome(requestId: request.id, saved: true)),
        ]
        for message in messages {
            let encoded = try WCMessageCodec.encode(quickLog: message)
            #expect(encoded[WCMessageCodec.Key.quickLogVersion] as? Int == 1)
            let decoded = try WCMessageCodec.decodeQuickLog(from: encoded)
            #expect(decoded == message)
        }
    }

    @Test func wrongVersionIsRejected() throws {
        var encoded = try WCMessageCodec.encode(
            quickLog: .confirm(QuickLogConfirm(requestId: UUID(), accept: false)))
        encoded[WCMessageCodec.Key.quickLogVersion] = 99
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(99)) {
            try WCMessageCodec.decodeQuickLog(from: encoded)
        }
    }

    @Test func unrelatedMessageIsRejectedNotMisdecoded() {
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(0)) {
            try WCMessageCodec.decodeQuickLog(from: ["something": "else"])
        }
    }
}

// MARK: - Service on the scripted pipeline

@MainActor
struct QuickLogServiceTests {
    private func tempQueue() -> PendingMealQueue {
        PendingMealQueue(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("quicklog-test-\(UUID().uuidString).json"))
    }

    /// Typed captures run the deterministic parsers even in the scripted pipeline (fresh item
    /// ids each time), so the exact-number tests speak a stated calorie + "from <seller>" —
    /// the same real rungs a dictated sentence would hit. The plain-text case exercises the
    /// honest estimate bottom rung.
    private func makeService(
        recorder: InMemoryNutritionRecorder = InMemoryNutritionRecorder(),
        queue: PendingMealQueue? = nil
    ) -> (QuickLogService, InMemoryNutritionRecorder, ScriptedMealPipeline) {
        let pipeline = ScriptedMealPipeline.demoGroceryReceipt()
        let service = QuickLogService(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: recorder, queue: queue
        )
        return (service, recorder, pipeline)
    }

    private let statedText = "chicken salad from Saladworks 460 calories"

    @Test func draftResolvesAndSummarizes() async {
        let (service, _, _) = makeService()
        let request = QuickLogRequest(text: statedText)
        let draft = await service.draft(for: request)
        #expect(draft?.requestId == request.id)
        #expect(draft?.name == "Chicken salad")
        #expect(draft?.totalKcal == 460)
        #expect(draft?.isEstimate == false)
        #expect(draft?.sourceLabel == "your number")
        #expect(draft?.itemCount == 1)
    }

    @Test func plainTextFallsToHonestEstimate() async {
        let (service, _, _) = makeService()
        let draft = await service.draft(for: QuickLogRequest(text: "chicken salad"))
        #expect(draft?.isEstimate == true)
        #expect(draft?.sourceLabel == "estimate")
    }

    @Test func confirmCommitsExactlyTheDraftedNumbers() async {
        let recorder = InMemoryNutritionRecorder()
        let queue = tempQueue()
        let (service, _, _) = makeService(recorder: recorder, queue: queue)
        let request = QuickLogRequest(text: statedText)
        _ = await service.draft(for: request)

        let outcome = await service.commit(QuickLogConfirm(requestId: request.id, accept: true))
        #expect(outcome.saved)
        #expect(recorder.entries.count == 1)
        #expect(recorder.entries.first?.facts.energy.midpointKcal == 460)
        #expect(recorder.entries.first?.seller?.name == "Saladworks")
        // Durability rows drained on confirmed writes.
        #expect(queue.pending.isEmpty)
    }

    @Test func declineDiscardsWithoutRecording() async {
        let recorder = InMemoryNutritionRecorder()
        let (service, _, _) = makeService(recorder: recorder)
        let request = QuickLogRequest(text: statedText)
        _ = await service.draft(for: request)

        let outcome = await service.commit(QuickLogConfirm(requestId: request.id, accept: false))
        #expect(!outcome.saved)
        #expect(recorder.entries.isEmpty)

        // The draft is gone — a late duplicate confirm can't double-record.
        let replay = await service.commit(QuickLogConfirm(requestId: request.id, accept: true))
        #expect(!replay.saved)
    }

    @Test func failedWriteReportsUnsavedAndKeepsDurabilityRow() async {
        let recorder = InMemoryNutritionRecorder()
        recorder.failWrites = true
        let queue = tempQueue()
        let (service, _, _) = makeService(recorder: recorder, queue: queue)
        let request = QuickLogRequest(text: statedText)
        _ = await service.draft(for: request)

        let outcome = await service.commit(QuickLogConfirm(requestId: request.id, accept: true))
        #expect(!outcome.saved)                       // never a fake "Logged" (N6)
        #expect(queue.pending.count == 1)             // retry rides the normal drain
        #expect(queue.pending.first?.needsReview == false)
    }

    @Test func unknownRequestCommitIsSafelyUnsaved() async {
        let (service, recorder, _) = makeService()
        let outcome = await service.commit(QuickLogConfirm(requestId: UUID(), accept: true))
        #expect(!outcome.saved)
        #expect(recorder.entries.isEmpty)
    }

    @Test func offlineRequestParksAsReviewRow() async {
        let queue = tempQueue()
        let (service, recorder, _) = makeService(queue: queue)
        service.enqueueForReview(QuickLogRequest(text: "two tacos from chipotle"))

        let row = queue.pending.first
        #expect(row?.needsReview == true)
        #expect(row?.sourceText == "two tacos from chipotle")
        #expect(recorder.entries.isEmpty)
    }
}

// MARK: - Review rows vs the launch drain

@MainActor
struct PendingReviewDrainTests {
    private func tempQueue() -> PendingMealQueue {
        PendingMealQueue(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("review-drain-\(UUID().uuidString).json"))
    }

    @Test func resumePendingSkipsReviewRowsButDrainsRetryRows() async {
        let queue = tempQueue()
        // A normal retry row (crashed mid-commit) and a review row (offline quick-log).
        queue.enqueue(PendingMealQueue.PendingItem(
            date: Date(),
            item: PendingMealQueue.PendingDraft(name: "Yogurt", quantity: 1),
            seller: nil, answers: []
        ))
        queue.enqueue(PendingMealQueue.PendingItem(
            date: Date(),
            item: PendingMealQueue.PendingDraft(name: "two tacos", quantity: 1),
            seller: nil, answers: [],
            needsReview: true, sourceText: "two tacos"
        ))

        let pipeline = ScriptedMealPipeline.demoGroceryReceipt()
        let recorder = InMemoryNutritionRecorder()
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: recorder, queue: queue
        )
        await controller.resumePending()

        #expect(recorder.entries.map(\.name) == ["Yogurt"])   // review row untouched
        #expect(queue.pending.count == 1)
        #expect(queue.pending.first?.needsReview == true)
    }

    @Test func preP6RowsDecodeAsRetryRows() throws {
        // A build-15-era row (no needsReview/sourceText keys) must decode as a normal
        // retry row — Codable evolution contract.
        let json = """
        [{"id":"\(UUID().uuidString)","date":700000000,
          "item":{"name":"Yogurt","quantity":1},"answers":[]}]
        """
        let rows = try JSONDecoder().decode([PendingMealQueue.PendingItem].self, from: Data(json.utf8))
        #expect(rows.first?.needsReview == false)
        #expect(rows.first?.sourceText == nil)
    }
}
