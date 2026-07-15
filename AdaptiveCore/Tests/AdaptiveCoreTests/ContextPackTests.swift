import Foundation
import Testing
@testable import AdaptiveCore

struct ContextPackTests {
    private let now = Date(timeIntervalSince1970: 1_751_700_000) // fixed "now"

    private func makeInput(
        snapshot: HealthSnapshot? = nil,
        nutrition: NutritionDigest? = nil,
        journal: [ProgressionJournalEntry] = []
    ) -> ContextPackInput {
        let routine = Routine(
            name: "Strength Circuit",
            cards: [.exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20)))]
        )
        let run = Routine(name: "Morning Run", cards: [.run(RunCard())])
        return ContextPackInput(routines: [routine, run], journal: journal,
                                snapshot: snapshot, nutrition: nutrition, now: now)
    }

    private func journalEntry(daysAgo: Int, subject: String = "Goblet Squat",
                              kind: ProgressionJournalEntry.Kind = .micro) -> ProgressionJournalEntry {
        ProgressionJournalEntry(
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            routineId: UUID(), routineName: "Strength Circuit",
            subject: subject, changeText: "10 → 11 reps", reason: "clean session",
            kind: kind, perceivedEffort: 5
        )
    }

    @Test func everyUseCaseRenders() {
        for useCase in ContextPackUseCase.allCases {
            let pack = ContextPackComposer.pack(
                useCase: useCase, scope: useCase.preset,
                input: makeInput(snapshot: HealthSnapshot(vo2Max: 41),
                                 nutrition: NutritionDigest(days: [.init(date: now, totalKcal: 2100)]),
                                 journal: [journalEntry(daysAgo: 2)])
            )
            #expect(!pack.promptText.isEmpty)
            #expect(!pack.includesLine.isEmpty)
            #expect(pack.title == useCase.title)
        }
    }

    @Test func jsonFormatOnlyOnImportCapableCases() {
        let input = makeInput()
        for useCase in ContextPackUseCase.allCases {
            let pack = ContextPackComposer.pack(useCase: useCase, scope: useCase.preset, input: input)
            let asksForJSON = pack.promptText.contains("single JSON code block")
            #expect(asksForJSON == useCase.wantsJSONResponse,
                    "\(useCase) JSON ask mismatch")
            if !useCase.wantsJSONResponse {
                #expect(pack.promptText.contains("plain prose"))
            } else {
                // The import-capable cases must carry the vocabulary + schema rules so the
                // reply survives CoachProposalValidator (same contract as primingPrompt).
                #expect(pack.promptText.contains("goblet_squat"))
                #expect(pack.promptText.contains("weightLb"))
                #expect(pack.promptText.contains(RoutineExchange.schemaName))
            }
        }
    }

    @Test func programDesignCarriesRoutinesJSONAndProgressionProse() {
        let pack = ContextPackComposer.pack(useCase: .programDesign,
                                            scope: .init(includeFitnessSnapshot: false),
                                            input: makeInput())
        #expect(pack.promptText.contains("```json"))
        #expect(pack.promptText.contains("Strength Circuit"))
        #expect(pack.promptText.contains("Current working levels"))
    }

    @Test func scopeSubsetsRoutinesAndIncludesLineCounts() {
        let input = makeInput()
        let onlyFirst = ContextPackScope(routineIds: [input.routines[0].id])
        let pack = ContextPackComposer.pack(useCase: .programDesign, scope: onlyFirst, input: input)
        #expect(pack.promptText.contains("Strength Circuit"))
        #expect(!pack.promptText.contains("Morning Run"))
        #expect(pack.includesLine.contains("1 routine"))
    }

    @Test func nilSnapshotFieldsAreOmittedNeverFabricated() {
        let snapshot = HealthSnapshot(restingHeartRate: 58)
        let pack = ContextPackComposer.pack(
            useCase: .checkIn,
            scope: .init(includeFitnessSnapshot: true),
            input: makeInput(snapshot: snapshot)
        )
        #expect(pack.promptText.contains("Resting heart rate: 58 bpm"))
        #expect(!pack.promptText.contains("VO2max"))
        #expect(!pack.promptText.contains("Days since last workout"))
    }

    @Test func emptySnapshotSectionIsDropped() {
        let pack = ContextPackComposer.pack(
            useCase: .checkIn,
            scope: .init(includeFitnessSnapshot: true),
            input: makeInput(snapshot: HealthSnapshot())
        )
        #expect(!pack.promptText.contains("fitness snapshot (from Apple Health)"))
    }

    @Test func journalWindowFiltersAndRendersReasons() {
        let journal = [journalEntry(daysAgo: 2), journalEntry(daysAgo: 45, subject: "Old Move")]
        let pack = ContextPackComposer.pack(
            useCase: .plateau,
            scope: .init(journalDays: 30),
            input: makeInput(journal: journal)
        )
        #expect(pack.promptText.contains("Goblet Squat 10 → 11 reps — clean session (effort 5)"))
        #expect(!pack.promptText.contains("Old Move"))
    }

    @Test func declinedJournalEntriesSayHeldByMe() {
        let pack = ContextPackComposer.pack(
            useCase: .checkIn,
            scope: .init(journalDays: 30),
            input: makeInput(journal: [journalEntry(daysAgo: 1, kind: .declined)])
        )
        #expect(pack.promptText.contains("[held by me]"))
    }

    @Test func nutritionSectionRendersTargetDaysAndSellers() {
        let nutrition = NutritionDigest(
            days: [.init(date: now, totalKcal: 2100, proteinGrams: 130)],
            calorieTarget: 2200,
            frequentSellers: ["Saladworks", "Chipotle"]
        )
        let pack = ContextPackComposer.pack(
            useCase: .mealPlanning, scope: ContextPackUseCase.mealPlanning.preset,
            input: makeInput(nutrition: nutrition)
        )
        #expect(pack.promptText.contains("Daily calorie target: 2200 kcal"))
        #expect(pack.promptText.contains("2100 kcal · 130g protein"))
        #expect(pack.promptText.contains("Saladworks, Chipotle"))
        // Meal planning defaults routines off.
        #expect(!pack.promptText.contains("```json"))
        #expect(pack.includesLine.contains("no routines"))
    }

    @Test func includesLineIsHonestAboutOmissions() {
        let pack = ContextPackComposer.pack(
            useCase: .programDesign,
            scope: .init(includeFitnessSnapshot: false, journalDays: nil, includeNutrition: false),
            input: makeInput()
        )
        #expect(pack.includesLine == "2 routines · no snapshot · no progression history · no meals")
    }

    /// P27: the scope PROMISED a snapshot but Health returned nothing — the composed pack's
    /// includes-line must reconcile to "no snapshot", and `includedSections` must expose the
    /// shortfall so the export sheet can say so.
    @Test func promisedButEmptySnapshotReconcilesTheIncludesLine() {
        let scope = ContextPackScope(includeFitnessSnapshot: true, journalDays: 30)
        let input = makeInput(snapshot: HealthSnapshot())   // promised, composes empty
        let pack = ContextPackComposer.pack(useCase: .programDesign, scope: scope, input: input)

        #expect(!pack.includedSections.contains(.fitnessSnapshot))
        #expect(!pack.includedSections.contains(.progressionHistory))   // empty journal window
        #expect(pack.includedSections.contains(.routines))
        #expect(pack.includesLine == "2 routines · no snapshot · no progression history · no meals")
        // The scope-derived line (the live pre-export footer) still shows the promise — the
        // difference is exactly what the sheet warns about.
        let promised = ContextPackComposer.includesLine(useCase: .programDesign, scope: scope, input: input)
        #expect(promised.contains("fitness snapshot"))
        #expect(scope.promisedSections.subtracting(pack.includedSections)
            == [.fitnessSnapshot, .progressionHistory])
    }

    @Test func composedSectionsMatchWhatActuallyRendered() {
        let pack = ContextPackComposer.pack(
            useCase: .checkIn, scope: ContextPackUseCase.checkIn.preset,
            input: makeInput(snapshot: HealthSnapshot(vo2Max: 41),
                             nutrition: NutritionDigest(days: [.init(date: now, totalKcal: 2100)]),
                             journal: [journalEntry(daysAgo: 2)])
        )
        #expect(pack.includedSections == [.routines, .fitnessSnapshot, .progressionHistory, .nutrition])
        #expect(pack.includesLine == "2 routines · fitness snapshot · 90-day progression · recent meals")
    }

    @Test func healthDataFlagDrivesDisclosure() {
        #expect(ContextPackScope(includeFitnessSnapshot: true).includesHealthData)
        #expect(ContextPackScope(includeNutrition: true).includesHealthData)
        #expect(!ContextPackScope(journalDays: 90).includesHealthData)
    }
}
