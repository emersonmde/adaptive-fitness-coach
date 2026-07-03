import Foundation
import Testing
@testable import AdaptiveCore

/// Build-8 recorder evolution: day-parametrized intake, active energy, replace-with-rollback.
struct RecorderEvolutionTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func entry(name: String, dayOffset: Int, hour: Int = 12, kcal: Double = 400) -> MealEntry {
        let base = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: hour))!
        let date = calendar.date(byAdding: .day, value: dayOffset, to: base)!
        return MealEntry(
            date: date, name: name,
            facts: NutritionFacts(energy: .exact(kcal: kcal)),
            provenance: .userStated
        )
    }

    @Test func intakeFiltersByDay() async throws {
        let recorder = InMemoryNutritionRecorder(calendar: calendar)
        recorder.seed([
            entry(name: "today lunch", dayOffset: 0),
            entry(name: "today dinner", dayOffset: 0, hour: 18, kcal: 600),
            entry(name: "yesterday", dayOffset: -1),
            entry(name: "last week", dayOffset: -7),
        ])
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9))!

        let today = try await recorder.intake(on: anchor)
        #expect(today.entries.map(\.name) == ["today lunch", "today dinner"])
        #expect(today.totalKcal == 1000)

        let yesterday = try await recorder.intake(
            on: calendar.date(byAdding: .day, value: -1, to: anchor)!
        )
        #expect(yesterday.entries.map(\.name) == ["yesterday"])
    }

    @Test func intakeAcrossDSTTransition() async throws {
        // US DST spring-forward 2026-03-08 (America/New_York): the 23-hour day must still
        // contain its own entries and not leak into neighbors.
        let recorder = InMemoryNutritionRecorder(calendar: calendar)
        let dstDayNoon = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let dayBefore = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        recorder.seed([
            MealEntry(date: dstDayNoon, name: "dst lunch", facts: NutritionFacts(energy: .exact(kcal: 500)), provenance: .userStated),
            MealEntry(date: dayBefore, name: "late snack", facts: NutritionFacts(energy: .exact(kcal: 200)), provenance: .userStated),
        ])
        let dst = try await recorder.intake(on: dstDayNoon)
        #expect(dst.entries.map(\.name) == ["dst lunch"])
    }

    @Test func replaceSwapsTheEntry() async throws {
        let recorder = InMemoryNutritionRecorder(calendar: calendar)
        let original = entry(name: "Curry", dayOffset: 0)
        try await recorder.record(original)
        let edited = original.edited(kcal: 500)
        try await recorder.replace(original, with: edited)

        #expect(recorder.entries.count == 1)
        #expect(recorder.entries[0].facts.energy == .exact(kcal: 500))
        #expect(recorder.entries[0].id == original.id)
    }

    @Test func replaceRollsBackWhenTheRewriteFails() async throws {
        let recorder = InMemoryNutritionRecorder(calendar: calendar)
        let original = entry(name: "Curry", dayOffset: 0)
        try await recorder.record(original)

        recorder.failNextWrites = 1   // the edited write fails; the restore write succeeds
        await #expect(throws: (any Error).self) {
            try await recorder.replace(original, with: original.edited(kcal: 500))
        }
        #expect(recorder.entries.count == 1)
        #expect(recorder.entries[0].facts.energy == .exact(kcal: 400))   // original restored
    }

    @Test func activeEnergyIsPerDayAndInformational() async throws {
        let recorder = InMemoryNutritionRecorder(calendar: calendar)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9))!
        recorder.setActiveEnergy(430, on: anchor)
        #expect(try await recorder.activeEnergyBurned(on: anchor) == 430)
        #expect(try await recorder.activeEnergyBurned(
            on: calendar.date(byAdding: .day, value: -1, to: anchor)!
        ) == 0)
    }

    @Test func todayIntakeConvenienceStillWorks() async throws {
        let recorder = InMemoryNutritionRecorder()
        try await recorder.record(MealEntry(
            date: Date(), name: "Now",
            facts: NutritionFacts(energy: .exact(kcal: 300)),
            provenance: .userStated
        ))
        let today = try await recorder.todayIntake()
        #expect(today.totalKcal == 300)
    }
}
