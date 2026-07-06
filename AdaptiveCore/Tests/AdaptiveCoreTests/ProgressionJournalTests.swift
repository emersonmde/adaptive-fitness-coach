import Foundation
import Testing
@testable import AdaptiveCore

// MARK: - Policy evaluations carry reasons + the structural flag (P6)

struct StrengthEvaluationTests {
    private let policy = StrengthProgressionPolicy()
    private var squat: Exercise { ExerciseLibrary.exercise(id: "goblet_squat")! }

    private func outcome(
        planned: Int = 3, completed: Int = 3,
        reps: [Int], prescribed: Int = 10,
        unrecovered: Int = 0, lowered: Bool = false
    ) -> StrengthExerciseOutcome {
        StrengthExerciseOutcome(
            exerciseId: "goblet_squat", setsPlanned: planned, setsCompleted: completed,
            completedRepsPerSet: reps, prescribedReps: prescribed,
            unrecoveredRests: unrecovered, weightManuallyLowered: lowered
        )
    }

    @Test func cleanAdvanceBelowTopIsNotStructural() {
        let eval = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [10, 10, 10]), endedEarly: false
        )
        #expect(eval.decision == .advance)
        #expect(eval.reason == .cleanSession)
        #expect(!eval.steppedLoad)
        #expect(eval.next.reps == 11)
    }

    @Test func bandToppedLoadStepIsStructural() {
        let eval = policy.evaluate(
            current: StrengthPrescription(reps: 12, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [12, 12, 13], prescribed: 12), endedEarly: false
        )
        #expect(eval.steppedLoad)
        #expect(eval.reason == .bandTopped)
        #expect(eval.next.weight == .lb(25))
        #expect(eval.next.reps == 8)
    }

    @Test func gridSnapOnHoldIsNotAStructuralStep() {
        // The trailing grid snap moves a legacy 22.5 on a plain hold — that must never read
        // as a band-topped step (the flag is set inside the branch, not by weight comparison).
        let curl = ExerciseLibrary.exercise(id: "db_curl")!
        let eval = policy.evaluate(
            current: StrengthPrescription(reps: 12, weight: .lb(22.5)), exercise: curl,
            outcome: StrengthExerciseOutcome(
                exerciseId: "db_curl", setsPlanned: 3, setsCompleted: 3,
                completedRepsPerSet: [11, 12, 12], prescribedReps: 12
            ),
            endedEarly: false
        )
        #expect(eval.decision == .hold)
        #expect(!eval.steppedLoad)
        #expect(eval.next.weight == .lb(20))
    }

    @Test func highEffortHoldCarriesTheRating() {
        let eval = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [10, 10, 10]), endedEarly: false, perceivedEffort: 9
        )
        #expect(eval.decision == .hold)
        #expect(eval.reason == .highEffort(9))
    }

    @Test func unrecoveredRestsExplainTheHold() {
        let eval = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [10, 10, 10], unrecovered: 2), endedEarly: false
        )
        #expect(eval.decision == .hold)
        #expect(eval.reason == .unrecoveredRests)
    }

    @Test func easeReasonsFollowStrugglePrecedence() {
        let lowered = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [10, 10, 10], lowered: true), endedEarly: false
        )
        #expect(lowered.reason == .loweredWeight)

        let short = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(reps: [8, 8, 10]), endedEarly: false
        )
        #expect(short.decision == .ease)
        #expect(short.reason == .shortSets)

        let bailed = policy.evaluate(
            current: StrengthPrescription(reps: 10, weight: .lb(20)), exercise: squat,
            outcome: outcome(planned: 4, completed: 1, reps: [10]), endedEarly: true
        )
        #expect(bailed.decision == .ease)
        #expect(bailed.reason == .endedEarly)
    }
}

struct RunEvaluationTests {
    private let policy = RunProgressionPolicy()

    private func clean(fastRecoveries: Int = 0, longest: TimeInterval = 0, effort: Int? = nil) -> RunSessionOutcome {
        RunSessionOutcome(
            plannedRunIntervals: 4, completedRunIntervals: 4, runBackOffCount: 0,
            walksHitCap: 0, fastRecoveries: fastRecoveries, longestRunSeconds: longest,
            perceivedEffort: effort
        )
    }

    @Test func cleanAdvanceWithoutShapeChangeIsMicro() {
        let eval = policy.evaluate(
            current: RunSeeds(runSeconds: 90, walkSeconds: 120),
            outcome: clean(), blockSeconds: 1200
        )
        #expect(eval.reason == .cleanSession)
        #expect(!eval.isStructural)
        #expect(eval.seeds.runSeconds > 90)
        #expect(eval.seeds.walkSeconds == 120)
    }

    @Test func walkShrinkIsStructural() {
        // Long runs past the threshold shrink the walk — the shape graduation P6 gates.
        let eval = policy.evaluate(
            current: RunSeeds(runSeconds: 200, walkSeconds: 120),
            outcome: clean(), blockSeconds: 1200
        )
        #expect(eval.seeds.walkSeconds < 120)
        #expect(eval.isStructural)
    }

    @Test func continuousCrossingIsStructural() {
        let eval = policy.evaluate(
            current: RunSeeds(runSeconds: 550, walkSeconds: 60),
            outcome: clean(), blockSeconds: 600
        )
        #expect(eval.seeds.runSeconds >= 600)
        #expect(eval.isStructural)
    }

    @Test func easingIsNeverStructural() {
        // Backing off changes the walk seed too, but is applied automatically by design
        // (bias toward backing off) — the gate must never delay an ease.
        let struggle = RunSessionOutcome(
            plannedRunIntervals: 4, completedRunIntervals: 2, runBackOffCount: 3, walksHitCap: 2
        )
        let eval = policy.evaluate(
            current: RunSeeds(runSeconds: 200, walkSeconds: 90),
            outcome: struggle, blockSeconds: 1200
        )
        #expect(eval.seeds.walkSeconds > 90)
        #expect(!eval.isStructural)
        #expect(eval.reason == .repeatedBackOffs)
    }

    @Test func strongSessionAndSnapReasons() {
        let strong = policy.evaluate(
            current: RunSeeds(runSeconds: 90, walkSeconds: 120),
            outcome: clean(fastRecoveries: 4), blockSeconds: 1200
        )
        #expect(strong.reason == .strongSession)

        let snapped = policy.evaluate(
            current: RunSeeds(runSeconds: 90, walkSeconds: 120),
            outcome: clean(longest: 300), blockSeconds: 1200
        )
        #expect(snapped.reason == .snapToCapacity)
        #expect(snapped.seeds.runSeconds == 300)
    }

    @Test func highEffortHoldCarriesTheRating() {
        let eval = policy.evaluate(
            current: RunSeeds(runSeconds: 90, walkSeconds: 120),
            outcome: clean(effort: 9), blockSeconds: 1200
        )
        #expect(eval.seeds == RunSeeds(runSeconds: 90, walkSeconds: 120))
        #expect(eval.reason == .highEffort(9))
    }

    @Test func nextSeedsWrapperMatchesEvaluate() {
        let current = RunSeeds(runSeconds: 200, walkSeconds: 120)
        let outcome = clean()
        #expect(policy.nextSeeds(current: current, outcome: outcome)
                == policy.evaluate(current: current, outcome: outcome, blockSeconds: 1200).seeds)
    }
}

// MARK: - Wire model v4

struct ProgressionBatchV4Tests {
    @Test func batchRoundTripsProposalsEffortAndReasons() throws {
        let batch = ProgressionBatch(
            routineId: UUID(),
            updates: [ProgressionUpdate(exerciseId: "db_curl", reps: 13, reason: "clean session")],
            runUpdates: [RunProgressionUpdate(cardId: UUID(), runSeconds: 150, walkSeconds: 120,
                                              reason: "clean session", blockSeconds: 1200)],
            proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8,
                                          reason: "topped the rep band")],
            runProposals: [RunProgressionUpdate(cardId: UUID(), runSeconds: 240, walkSeconds: 105,
                                                reason: "fast recovery on every walk", blockSeconds: 1200)],
            perceivedEffort: 6,
            sessionDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(batch)
        let decoded = try JSONDecoder().decode(ProgressionBatch.self, from: data)
        #expect(decoded == batch)
    }

    @Test func v3PayloadDecodesWithEmptyProposalLanes() throws {
        // A pre-v4 JSON body (no proposals/effort keys) must still decode — the batch shape
        // is tolerant even though the codec's version gate rejects cross-version *messages*.
        let json = """
        {"routineId":"\(UUID().uuidString)",
         "updates":[{"id":"\(UUID().uuidString)","exerciseId":"db_curl","reps":13,
                     "date":700000000}]}
        """
        let decoded = try JSONDecoder().decode(ProgressionBatch.self, from: Data(json.utf8))
        #expect(decoded.proposals.isEmpty)
        #expect(decoded.runProposals.isEmpty)
        #expect(decoded.perceivedEffort == nil)
        #expect(decoded.updates.first?.reason == nil)
    }

    @Test func codecIsAtV4AndRejectsOldVersions() throws {
        let batch = ProgressionBatch(routineId: UUID())
        var message = try WCMessageCodec.encode(progression: batch)
        #expect(message[WCMessageCodec.Key.progressionVersion] as? Int == 4)

        message[WCMessageCodec.Key.progressionVersion] = 3
        #expect(throws: WCMessageCodec.CodecError.unsupportedVersion(3)) {
            try WCMessageCodec.decodeProgression(from: message)
        }
    }
}

// MARK: - Journal + proposal stores + intake

@MainActor
struct ProgressionJournalStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-\(UUID().uuidString).json")
    }

    @Test func appendsNewestFirstAndPersists() throws {
        let url = tempURL()
        let journal = ProgressionJournal(fileURL: url)
        let older = ProgressionJournalEntry(
            date: Date(timeIntervalSince1970: 100), routineId: UUID(), routineName: "Legs",
            subject: "Goblet Squat", changeText: "12 → 13 reps", reason: "clean session", kind: .micro
        )
        let newer = ProgressionJournalEntry(
            date: Date(timeIntervalSince1970: 200), routineId: UUID(), routineName: "Legs",
            subject: "Run intervals", changeText: "2:00 → 2:30 run", reason: nil, kind: .confirmed
        )
        journal.append([older])
        journal.append([newer])
        #expect(journal.entries.map(\.subject) == ["Run intervals", "Goblet Squat"])

        let reloaded = ProgressionJournal(fileURL: url)
        #expect(reloaded.entries == journal.entries)
    }

    @Test func capDropsOldestRows() {
        let journal = ProgressionJournal(fileURL: tempURL(), cap: 3)
        let rows = (0..<5).map { i in
            ProgressionJournalEntry(
                date: Date(timeIntervalSince1970: TimeInterval(i)), routineId: UUID(),
                routineName: "R", subject: "S\(i)", changeText: "c", reason: nil, kind: .micro
            )
        }
        journal.append(rows)
        #expect(journal.entries.count == 3)
        #expect(journal.entries.first?.subject == "S4")
        #expect(journal.entries.last?.subject == "S2")
    }

    @Test func corruptFileIsSidecarredNotCrashed() throws {
        let url = tempURL()
        try Data("not json".utf8).write(to: url)
        let journal = ProgressionJournal(fileURL: url)
        #expect(journal.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }
}

@MainActor
struct ProgressionIntakeTests {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    /// A routine with one squat card (10 reps @ 20 lb) and one run card.
    private func makeWorld() -> (RoutineStore, ProgressionJournal, ProgressionProposalStore, Routine, UUID) {
        let runCard = RunCard(durationMinutes: 20, runSeconds: 120, walkSeconds: 120, seedsCalibrated: true)
        let routine = Routine(
            name: "Full Body",
            cards: [
                .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
                .run(runCard),
            ]
        )
        let store = RoutineStore(fileURL: tempURL("routines"))
        store.add(routine)
        return (store, ProgressionJournal(fileURL: tempURL("journal")),
                ProgressionProposalStore(fileURL: tempURL("proposals")), routine, runCard.id)
    }

    @Test func microUpdatesApplyAndJournalWithOldValues() {
        let (store, journal, proposals, routine, _) = makeWorld()
        let batch = ProgressionBatch(
            routineId: routine.id,
            updates: [ProgressionUpdate(exerciseId: "goblet_squat", reps: 11, reason: "clean session")],
            perceivedEffort: 5
        )
        ProgressionIntake.receive(batch, store: store, journal: journal, proposals: proposals)

        #expect(store.routines.first?.exerciseItems.first?.reps == 11)
        let entry = journal.entries.first
        #expect(entry?.kind == .micro)
        #expect(entry?.subject == "Goblet Squat")
        #expect(entry?.changeText == "10 → 11 reps")
        #expect(entry?.reason == "clean session")
        #expect(entry?.perceivedEffort == 5)
        #expect(proposals.proposals.isEmpty)
    }

    @Test func proposalsAreStashedNotApplied() {
        let (store, journal, proposals, routine, _) = makeWorld()
        let batch = ProgressionBatch(
            routineId: routine.id,
            proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8,
                                          reason: "topped the rep band")],
            perceivedEffort: 6
        )
        ProgressionIntake.receive(batch, store: store, journal: journal, proposals: proposals)

        #expect(store.routines.first?.exerciseItems.first?.seedWeight == .lb(20)) // untouched
        #expect(journal.entries.isEmpty)                                          // nothing applied yet
        #expect(proposals.proposals.count == 1)
    }

    @Test func confirmAppliesJournalsAndClears() {
        let (store, journal, proposals, routine, _) = makeWorld()
        ProgressionIntake.receive(
            ProgressionBatch(
                routineId: routine.id,
                proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8,
                                              reason: "topped the rep band")]
            ),
            store: store, journal: journal, proposals: proposals
        )
        let id = proposals.proposals.first!.id
        ProgressionIntake.confirm(id, store: store, journal: journal, proposals: proposals)

        #expect(store.routines.first?.exerciseItems.first?.seedWeight == .lb(25))
        #expect(store.routines.first?.exerciseItems.first?.reps == 8)
        let entry = journal.entries.first
        #expect(entry?.kind == .confirmed)
        #expect(entry?.changeText == "20 lb → 25 lb · reps reset to 8")
        #expect(proposals.proposals.isEmpty)

        // Double-confirm is a no-op.
        ProgressionIntake.confirm(id, store: store, journal: journal, proposals: proposals)
        #expect(journal.entries.count == 1)
    }

    @Test func declineHoldsAndJournalsHonestly() {
        let (store, journal, proposals, routine, _) = makeWorld()
        ProgressionIntake.receive(
            ProgressionBatch(
                routineId: routine.id,
                proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8,
                                              reason: "topped the rep band")]
            ),
            store: store, journal: journal, proposals: proposals
        )
        ProgressionIntake.decline(proposals.proposals.first!.id,
                                  store: store, journal: journal, proposals: proposals)

        #expect(store.routines.first?.exerciseItems.first?.seedWeight == .lb(20)) // held
        #expect(journal.entries.first?.kind == .declined)
        #expect(proposals.proposals.isEmpty)
    }

    @Test func runProposalConfirmRendersShapeChange() {
        let (store, journal, proposals, routine, cardId) = makeWorld()
        ProgressionIntake.receive(
            ProgressionBatch(
                routineId: routine.id,
                runProposals: [RunProgressionUpdate(cardId: cardId, runSeconds: 240, walkSeconds: 105,
                                                    reason: "fast recovery on every walk",
                                                    blockSeconds: 1200)]
            ),
            store: store, journal: journal, proposals: proposals
        )
        ProgressionIntake.confirm(proposals.proposals.first!.id,
                                  store: store, journal: journal, proposals: proposals)

        #expect(store.routines.first?.firstRunCard?.runSeconds == 240)
        #expect(store.routines.first?.firstRunCard?.walkSeconds == 105)
        let entry = journal.entries.first
        #expect(entry?.subject == "Run intervals")
        #expect(entry?.changeText == "2 min → 4 min run · 1m 45s walk")
    }

    @Test func continuousProposalRendersContinuous() {
        let (store, journal, proposals, routine, cardId) = makeWorld()
        ProgressionIntake.receive(
            ProgressionBatch(
                routineId: routine.id,
                runProposals: [RunProgressionUpdate(cardId: cardId, runSeconds: 1200, walkSeconds: 60,
                                                    reason: "ran well past the plan",
                                                    blockSeconds: 1200)]
            ),
            store: store, journal: journal, proposals: proposals
        )
        ProgressionIntake.confirm(proposals.proposals.first!.id,
                                  store: store, journal: journal, proposals: proposals)
        #expect(journal.entries.first?.changeText == "→ continuous")
    }

    @Test func newerProposalForSameExerciseSupersedes() {
        let (store, journal, proposals, routine, _) = makeWorld()
        for weight in [25.0, 30.0] {
            ProgressionIntake.receive(
                ProgressionBatch(
                    routineId: routine.id,
                    proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(weight), reps: 8)]
                ),
                store: store, journal: journal, proposals: proposals
            )
        }
        #expect(proposals.proposals.count == 1)
        #expect(proposals.proposals.first?.update?.weight == .lb(30))
    }

    @Test func unknownRoutineIsANoOp() {
        let (store, journal, proposals, _, _) = makeWorld()
        ProgressionIntake.receive(
            ProgressionBatch(routineId: UUID(),
                             proposals: [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25))]),
            store: store, journal: journal, proposals: proposals
        )
        #expect(proposals.proposals.isEmpty)
        #expect(journal.entries.isEmpty)
    }

    @Test func proposalsPersistAcrossRelaunch() {
        let url = tempURL("proposals")
        let store = ProgressionProposalStore(fileURL: url)
        store.add([PendingStructuralProposal(
            routineId: UUID(),
            update: ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 8)
        )])
        let reloaded = ProgressionProposalStore(fileURL: url)
        #expect(reloaded.proposals == store.proposals)
    }
}
