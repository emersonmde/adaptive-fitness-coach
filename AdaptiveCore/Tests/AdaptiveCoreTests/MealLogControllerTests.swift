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

    /// A capture started while browsing a past day prefills the when-row with THAT day
    /// (backfilling is the point of adding from a past day) — but a date the capture itself
    /// carries (receipt print / typed "yesterday") still outranks it.
    @Test func preferredDatePrefillsLoggedDate() async {
        let calendar = Calendar.current
        let viewedDay = calendar.date(byAdding: .day, value: -3, to: Date())!
        // A draft with no self-carried date (the demo receipt scripts a printed one).
        let undated = ScriptedMealPipeline(script: .init(draft: MealDraft(
            classification: .receipt, seller: nil, items: [DraftItem(name: "Salad")]
        )))
        let controller = MealLogController(
            pipeline: undated, resolver: undated.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(
            MealCapture(ocrLines: ["TRADER JOE'S", "CHKN CSR SLD"]),
            preferredDate: viewedDay
        )
        #expect(controller.phase == .confirming)
        #expect(calendar.isDate(controller.loggedDate, inSameDayAs: viewedDay))
        // Not a capture-supplied date — no "From the capture" honesty caption.
        #expect(controller.prefilledFromCapture == false)

        // The capture's own date wins over the viewed day.
        let printed = calendar.date(byAdding: .day, value: -1, to: Date())!
        let pipeline = ScriptedMealPipeline(script: .init(draft: MealDraft(
            classification: .receipt, seller: nil,
            items: [DraftItem(name: "Salad")], capturedAt: printed
        )))
        let dated = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await dated.beginCapture(MealCapture(ocrLines: ["receipt"]), preferredDate: viewedDay)
        #expect(calendar.isDate(dated.loggedDate, inSameDayAs: printed))
        #expect(dated.prefilledFromCapture == true)
    }

    @Test func identifyFailureIsHonestAndRetryable() async {
        let draft = MealDraft(classification: .receipt, seller: nil, items: [DraftItem(name: "x")])
        let pipeline = ScriptedMealPipeline(script: .init(draft: draft, identifyError: URLError(.timedOut)))
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(MealCapture(ocrLines: ["blur"]))
        // Build 10: failure keeps the flow sheet up (phase .failed) with the error and a
        // retry, instead of silently dropping to idle.
        #expect(controller.phase == .failed)
        #expect(controller.error != nil)
        // Retry re-runs identify on the same capture (still scripted to fail here).
        await controller.retryCapture()
        #expect(controller.phase == .failed)
        // Cancel is always an exit.
        controller.cancel()
        #expect(controller.phase == .idle)
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
        #expect(controller.phase == .failed)
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
        controller.setLoggedDate(Date())   // demo receipt prefills yesterday; log it today
        controller.setQuantity(ScriptedMealPipeline.DemoID.salad, quantity: 2)
        await controller.commit()
        let salad = try #require(recorder.entries.first { $0.name.contains("Caesar") })
        #expect(salad.quantity == 2)
        #expect(salad.facts.energy == .exact(kcal: 460))   // per-serving stays per-serving
        let intake = try await recorder.todayIntake()
        // 460×2 + 300 + estimate midpoint 475
        #expect(intake.totalKcal == 460 * 2 + 300 + 475)
    }

    // MARK: - Build 8: the when-row

    @Test func receiptDatePrefillsAndStampsEntries() async throws {
        let (controller, recorder) = makeController()   // demo receipt: yesterday 18:42
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        #expect(controller.prefilledFromCapture)
        #expect(controller.mealSlot == .dinner)         // 18:42 → dinner
        let calendar = Calendar.current
        #expect(!calendar.isDateInToday(controller.loggedDate))

        await controller.commit()
        let salad = try #require(recorder.entries.first { $0.name.contains("Caesar") })
        #expect(calendar.isDateInYesterday(salad.date))
        #expect(salad.meal == .dinner)

        // The pager finds it on yesterday, not today.
        let yesterday = try await recorder.intake(on: controller.loggedDate)
        #expect(!yesterday.entries.isEmpty)
        #expect(try await recorder.todayIntake().entries.isEmpty)
    }

    @Test func manualSlotSurvivesADateChange() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        controller.setMealSlot(.lunch)                  // user's choice
        controller.setLoggedDate(Date())                // date change re-suggests…
        #expect(controller.mealSlot == .lunch)          // …but never overrides the user
    }

    @Test func loggedDateNeverLandsInTheFuture() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        controller.setLoggedDate(Date().addingTimeInterval(86_400))
        #expect(controller.loggedDate <= Date())
    }

    @Test func typedEntryWithStatedCaloriesEndsUserStated() async throws {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(typedText: "salmon caesar salad, 400 calories"))
        #expect(controller.draft?.classification == .typed)
        #expect(controller.draft?.items.first?.name == "Salmon caesar salad")
        await controller.commit()

        let entry = try #require(recorder.entries.first)
        #expect(entry.facts.energy == .exact(kcal: 400))
        #expect(entry.provenance == .userStated)
    }

    // MARK: - Build 10: pre-commit lookups on the confirmation screen

    @Test func confirmationPreResolvesCheckedItemsOnly() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()

        // Checked items got numbers before any commit; the source rides along.
        let salad = controller.displayedNutrition(for: ScriptedMealPipeline.DemoID.salad)
        #expect(salad?.facts.energy == .exact(kcal: 460))
        guard case .database = salad?.provenance else {
            Issue.record("salad should show its database source pre-commit"); return
        }
        let curry = controller.displayedNutrition(for: ScriptedMealPipeline.DemoID.curry)
        #expect(curry?.facts.energy.isRange == true)   // honest estimate range, pre-commit

        // The pre-unchecked pantry item never spends a lookup (§5).
        #expect(controller.displayedNutrition(for: ScriptedMealPipeline.DemoID.pasta) == nil)
    }

    @Test func checkingAnItemStartsItsLookup() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()
        controller.toggleItem(ScriptedMealPipeline.DemoID.pasta)   // check the pantry item
        await controller.resolveOutstandingItems()
        #expect(controller.displayedNutrition(for: ScriptedMealPipeline.DemoID.pasta) != nil)
    }

    @Test func calorieOverrideBecomesUserStatedAndKeepsMacros() async throws {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()

        controller.setCalories(ScriptedMealPipeline.DemoID.salad, kcal: 520)
        let shown = controller.displayedNutrition(for: ScriptedMealPipeline.DemoID.salad)
        #expect(shown?.facts.energy == .exact(kcal: 520))
        #expect(shown?.provenance == .userStated)
        #expect(shown?.facts.proteinGrams == 39)   // macros kept — the user restated energy

        await controller.commit()
        let salad = try #require(recorder.entries.first { $0.name.contains("Caesar") })
        #expect(salad.facts.energy == .exact(kcal: 520))
        #expect(salad.provenance == .userStated)
    }

    @Test func renameInvalidatesAndReResolves() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()
        #expect(controller.resolutions[ScriptedMealPipeline.DemoID.salad] != nil)

        controller.editItemName(ScriptedMealPipeline.DemoID.salad, name: "Different Salad")
        // Invalidated immediately (the row goes back to "Looking up…"), then re-resolves.
        await controller.resolveOutstandingItems()
        #expect(controller.resolutions[ScriptedMealPipeline.DemoID.salad] != nil)
    }

    @Test func commitReusesTheNumbersTheScreenShowed() async {
        // A resolver whose adjudicator counts calls: pre-resolve spends the lookups, commit
        // must NOT spend them again.
        final class CountingAdjudicator: ExcerptAdjudicator, @unchecked Sendable {
            let inner: ScriptedAdjudicator
            var calls = 0
            init(pipeline: ScriptedMealPipeline) { inner = ScriptedAdjudicator(pipeline: pipeline) }
            func adjudicate(item: DraftItem, seller: Seller?, excerpts: [SearchExcerpt]) async throws -> ResolvedNutrition? {
                calls += 1
                return try await inner.adjudicate(item: item, seller: seller, excerpts: excerpts)
            }
        }
        let pipeline = ScriptedMealPipeline.demoGroceryReceipt()
        let counting = CountingAdjudicator(pipeline: pipeline)
        let resolver = MealResolver(
            barcodeDB: nil, searcher: ScriptedSearcher(), adjudicator: counting,
            agent: nil, estimator: ScriptedEstimator(pipeline: pipeline)
        )
        let recorder = InMemoryNutritionRecorder()
        let controller = MealLogController(
            pipeline: pipeline, resolver: resolver, recorder: recorder
        )
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()
        let callsAfterPreResolve = counting.calls
        #expect(callsAfterPreResolve == 3)   // the three checked items

        await controller.commit()
        #expect(counting.calls == callsAfterPreResolve)   // no re-lookup at Log
        #expect(recorder.entries.count == 3)
    }

    // MARK: - Review-hardening pins (build 11)

    @Test func doubleCommitRecordsEveryItemOnce() async {
        // The Log button can be tapped twice before phase flips (the auth await sits between
        // the guard and phase = .logging) — re-entrancy must not double-record.
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        async let first: Void = controller.commit()
        async let second: Void = controller.commit()
        _ = await (first, second)
        #expect(recorder.entries.count == 3)
    }

    @Test func statedCaloriesSurviveTheQueueRoundTrip() async throws {
        // App dies after Log but before the Health write confirms: the drain must record
        // the USER'S number, not re-run the ladder from the name alone.
        let queue = tempQueue()
        let recorder = InMemoryNutritionRecorder()
        recorder.failWrites = true
        let (controller, _) = makeController(recorder: recorder, queue: queue)
        await controller.beginCapture(MealCapture(typedText: "salmon salad, 400 calories"))
        await controller.commit()
        #expect(queue.pending.count == 1)

        // "Next launch": a fresh controller + working recorder drain the same queue.
        let (resumer, resumeRecorder) = makeController(queue: queue)
        await resumer.resumePending()
        let entry = try #require(resumeRecorder.entries.first)
        #expect(entry.facts.energy == .exact(kcal: 400))
        #expect(entry.provenance == .userStated)
    }

    @Test func chosenSlotSurvivesTheQueueRoundTrip() async throws {
        let queue = tempQueue()
        let recorder = InMemoryNutritionRecorder()
        recorder.failWrites = true
        let (controller, _) = makeController(recorder: recorder, queue: queue)
        await controller.beginCapture(MealCapture(typedText: "pad thai"))
        controller.setMealSlot(.dinner)   // explicit choice, whatever the hour
        await controller.commit()

        let (resumer, resumeRecorder) = makeController(queue: queue)
        await resumer.resumePending()
        let entry = try #require(resumeRecorder.entries.first)
        #expect(entry.meal == .dinner)
    }

    @Test func abortedCommitLeavesEveryItemQueued() async {
        // A new capture (generation bump) mid-commit must not lose items the record loop
        // hadn't reached — the Log tap queues the whole checked set up front.
        let pipeline = ScriptedMealPipeline.demoGroceryReceipt(delays: true)   // 500ms resolves
        let queue = tempQueue()
        let recorder = InMemoryNutritionRecorder()
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: recorder, queue: queue
        )
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        let commitTask = Task { await controller.commit() }
        while controller.phase != .logging { await Task.yield() }   // commit is under way
        controller.cancel()                                          // abandon mid-loop
        await commitTask.value
        // 3 checked items were queued at Log; recorded ones were removed; the rest remain.
        #expect(recorder.entries.count + queue.pending.count == 3)
        #expect(!queue.pending.isEmpty)
    }

    @Test func answerFlowsIntoTheReResolvedEstimate() async {
        // Answering a chip invalidates the item's number and re-resolves with the answer.
        final class AnswerSpy: PlateEstimator, @unchecked Sendable {
            var seen: [[QuestionAnswer]] = []
            func estimate(item: DraftItem, capture: MealCapture?, answers: [QuestionAnswer]) async throws -> ResolvedNutrition {
                seen.append(answers)
                return ResolvedNutrition(
                    facts: NutritionFacts(energy: .range(lowKcal: 100, highKcal: 200)),
                    provenance: .estimate(assumptions: ["test"])
                )
            }
        }
        let pipeline = ScriptedMealPipeline.demoGroceryReceipt()
        let spy = AnswerSpy()
        let resolver = MealResolver(barcodeDB: nil, searcher: nil, adjudicator: nil, agent: nil, estimator: spy)
        let controller = MealLogController(
            pipeline: pipeline, resolver: resolver, recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()

        let chickenID = ScriptedMealPipeline.DemoID.chicken
        controller.answer(QuestionAnswer(questionID: "portion", optionID: "whole"), itemID: chickenID)
        #expect(controller.resolutions[chickenID] == nil)   // invalidated immediately
        await controller.resolveOutstandingItems()
        #expect(controller.resolutions[chickenID] != nil)
        #expect(spy.seen.contains { $0.contains { $0.optionID == "whole" } })
    }

    @Test func renameDropsInheritedMacrosFromTheOverride() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.resolveOutstandingItems()
        let saladID = ScriptedMealPipeline.DemoID.salad
        controller.setCalories(saladID, kcal: 500)   // inherits the salad lookup's macros
        controller.editItemName(saladID, name: "Pad Thai")
        let shown = controller.displayedNutrition(for: saladID)
        #expect(shown?.facts.energy == .exact(kcal: 500))   // the user's number survives
        #expect(shown?.facts.proteinGrams == nil)           // the salad's macros don't
    }

    @Test func nonPositiveCalorieOverrideIsRejected() async {
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        controller.setCalories(ScriptedMealPipeline.DemoID.salad, kcal: 0)
        controller.setCalories(ScriptedMealPipeline.DemoID.salad, kcal: -50)
        #expect(controller.draft?.items.first { $0.id == ScriptedMealPipeline.DemoID.salad }?.statedFacts == nil)
    }

    @Test func staleErrorClearsOnSuccessfulCommit() async {
        let recorder = InMemoryNutritionRecorder()
        recorder.failAuthorization = true
        let (controller, _) = makeController(recorder: recorder)
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        await controller.commit()
        #expect(controller.error != nil)
        recorder.failAuthorization = false   // user fixed Health access
        await controller.commit()
        #expect(controller.phase == .done)
        #expect(controller.error == nil)
    }

    @Test func futureCaptureDateIsClampedOnPrefill() async {
        let future = Date().addingTimeInterval(7 * 86_400)
        let draft = MealDraft(
            classification: .receipt, seller: nil,
            items: [DraftItem(name: "x")], capturedAt: future
        )
        let pipeline = ScriptedMealPipeline(script: .init(draft: draft))
        let controller = MealLogController(
            pipeline: pipeline, resolver: pipeline.scriptedResolver(),
            recorder: InMemoryNutritionRecorder()
        )
        await controller.beginCapture(MealCapture(ocrLines: ["receipt"]))
        #expect(controller.loggedDate <= Date())
    }

    @Test func typedSellerClauseBecomesTheDraftSeller() async {
        // "from salad works" must survive as the seller (it drives seller-first lookup and
        // the verified-domain grading) — with a stated calorie clause composing correctly.
        let (controller, _) = makeController()
        await controller.beginCapture(MealCapture(typedText: "chicken ceaser salad from salad works, 550 calories"))
        #expect(controller.draft?.seller?.name == "Salad Works")
        #expect(controller.draft?.items.first?.name == "Chicken ceaser salad")
        #expect(controller.draft?.items.first?.statedFacts?.energy == .exact(kcal: 550))
    }

    @Test func commitCarriesTheSellerOntoEntries() async throws {
        // The seller survives all the way to the recorded entry (day rows + edit sheet
        // display it; the HK recorder round-trips it via metadata).
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(typedText: "chicken caesar salad from Saladworks"))
        await controller.commit()
        let entry = try #require(recorder.entries.first)
        #expect(entry.seller?.name == "Saladworks")

        // And it Codable-round-trips (pending-queue durability).
        let decoded = try JSONDecoder().decode(MealEntry.self, from: JSONEncoder().encode(entry))
        #expect(decoded.seller?.name == "Saladworks")
    }

    @Test func provenanceDetailLabelNamesTheActualSource() {
        #expect(Provenance.database(name: "eatthismuch.com", sourceURL: nil).detailLabel == "eatthismuch.com")
        #expect(Provenance.database(name: "database", sourceURL: URL(string: "https://www.nutritionix.com/x")).detailLabel == "www.nutritionix.com")
        #expect(Provenance.verified(sourceURL: URL(string: "https://saladworks.com/menu")).detailLabel == "verified · saladworks.com")
        #expect(Provenance.verified(sourceURL: nil).detailLabel == "verified")
        #expect(Provenance.estimate(assumptions: []).detailLabel == "estimate")
        #expect(Provenance.userStated.detailLabel == "your number")
    }

    @Test func typedYesterdayPhraseBackdates() async throws {
        let (controller, recorder) = makeController()
        await controller.beginCapture(MealCapture(typedText: "pad thai last night"))
        #expect(controller.prefilledFromCapture)
        #expect(controller.mealSlot == .dinner)
        await controller.commit()
        let entry = try #require(recorder.entries.first)
        #expect(Calendar.current.isDateInYesterday(entry.date))
        #expect(entry.meal == .dinner)
    }
}
