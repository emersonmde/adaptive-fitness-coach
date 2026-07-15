import Foundation
import Testing
@testable import AdaptiveCore

@MainActor
struct RoutineStoreTests {

    /// A store backed by a unique temp file, cleaned up by the OS temp dir.
    private func makeStore(onChange: (@MainActor ([Routine]) -> Void)? = nil) -> RoutineStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routines-\(UUID().uuidString).json")
        return RoutineStore(fileURL: url, onChange: onChange)
    }

    private func run(_ name: String = "Run", at time: ScheduleTime? = nil, days: Set<DayOfWeek> = [.monday]) -> Routine {
        Routine(name: name, repeatDays: days, scheduleTime: time, cards: [.run(RunCard())])
    }

    // MARK: - App Group migration (build 9)

    @Test func groupMigrationCopiesLegacyFileOnce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agmig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent("routines.json")
        let group = dir.appendingPathComponent("group-routines.json")

        // A pre-build-9 Documents store with one routine.
        let source = RoutineStore(fileURL: legacy)
        source.add(run("Legacy Run"))

        RoutineStore.migrateIfNeeded(from: legacy, to: group)
        let migrated = RoutineStore(fileURL: group)
        #expect(migrated.routines.map(\.name) == ["Legacy Run"])

        // Idempotent: a second migration never clobbers newer group data.
        migrated.add(run("Added In Group"))
        RoutineStore.migrateIfNeeded(from: legacy, to: group)
        let after = RoutineStore(fileURL: group)
        #expect(after.routines.count == 2)
    }

    @Test func groupMigrationNoopsWithoutLegacyFile() {
        let dir = FileManager.default.temporaryDirectory
        let legacy = dir.appendingPathComponent("missing-\(UUID().uuidString).json")
        let group = dir.appendingPathComponent("group-\(UUID().uuidString).json")
        RoutineStore.migrateIfNeeded(from: legacy, to: group)
        #expect(!FileManager.default.fileExists(atPath: group.path))
    }

    @Test func addPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routines-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        let routine = run("Morning Run")
        store.add(routine)

        // A fresh store reading the same file sees the persisted routine.
        let reloaded = RoutineStore(fileURL: url)
        #expect(reloaded.routines == [routine])
    }

    @Test func updateReplacesMatchingRoutine() {
        let store = makeStore()
        var routine = run("Run")
        store.add(routine)
        routine.name = "Renamed"
        store.update(routine)
        #expect(store.routines.count == 1)
        #expect(store.routines.first?.name == "Renamed")
    }

    @Test func removeDeletesById() {
        let store = makeStore()
        let routine = run()
        store.add(routine)
        store.remove(id: routine.id)
        #expect(store.routines.isEmpty)
    }

    @Test func localMutationsBroadcast() {
        var broadcasts = 0
        let store = makeStore { _ in broadcasts += 1 }
        let routine = run()
        store.add(routine)
        store.update(routine)
        store.remove(id: routine.id)
        #expect(broadcasts == 3)
    }

    @Test func syncDoesNotBroadcast() {
        var broadcasts = 0
        let store = makeStore { _ in broadcasts += 1 }
        store.replaceFromSync([run("A"), run("B")])
        #expect(broadcasts == 0)
        #expect(store.routines.count == 2)
    }

    @Test func importUpdatesByNameKeepingIdAndAddsNew() {
        let store = makeStore()
        let existing = run("Push Day", days: [.monday])
        store.add(existing)

        var revised = run("Push Day", days: [.tuesday])   // same name, new content/days
        revised.cards = [.exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 12, seedWeight: .lb(25)))]
        let fresh = run("Pull Day", days: [.thursday])

        let result = store.importRoutines([revised, fresh])
        #expect(result.updated == 1)
        #expect(result.added == 1)
        #expect(store.routines.count == 2)
        // The updated routine keeps the original id (so schedules/calendar survive).
        let push = store.routines.first { $0.name == "Push Day" }
        #expect(push?.id == existing.id)
        #expect(push?.repeatDays == [.tuesday])
        #expect(push?.exerciseItems.first?.seedWeight == .lb(25))
    }

    @Test func importMatchesNamesFoldedSoTheGraftNeverMissesOnCase() {
        // Build 11 pin: the exchange contract tells the model "the app matches by name" —
        // an LLM's "push day " for "Push Day" must merge (else: duplicate routine, silent
        // graft bypass). The existing routine keeps its own casing and identity.
        let store = makeStore()
        let existing = run("Push Day", days: [.monday])
        store.add(existing)
        let revised = run("  push day ", days: [.friday])
        let result = store.importRoutines([revised])
        #expect(result.updated == 1)
        #expect(result.added == 0)
        #expect(store.routines.count == 1)
        #expect(store.routines.first?.name == "Push Day")
        #expect(store.routines.first?.id == existing.id)
    }

    @Test func routinesOnDaySortedByTime() {
        let store = makeStore()
        store.add(run("Evening", at: ScheduleTime(hour: 18, minute: 0), days: [.monday]))
        store.add(run("Morning", at: ScheduleTime(hour: 7, minute: 0), days: [.monday]))
        let monday = store.routines(on: .monday)
        #expect(monday.map(\.name) == ["Morning", "Evening"])
    }

    @Test func nextRoutineFindsLaterToday() {
        let store = makeStore()
        store.add(run("Later", at: ScheduleTime(hour: 18, minute: 0), days: [.monday]))
        let next = store.nextRoutine(fromWeekday: .monday, hour: 9, minute: 0)
        #expect(next?.name == "Later")
    }

    @Test func nextRoutineWrapsToFutureDay() {
        let store = makeStore()
        store.add(run("Wednesday", at: ScheduleTime(hour: 7, minute: 0), days: [.wednesday]))
        // It's Monday evening; the only routine is Wednesday morning.
        let next = store.nextRoutine(fromWeekday: .monday, hour: 20, minute: 0)
        #expect(next?.name == "Wednesday")
    }

    @Test func nextRoutineNilWhenEmpty() {
        let store = makeStore()
        #expect(store.nextRoutine(fromWeekday: .monday, hour: 9, minute: 0) == nil)
    }

    @Test func nextRoutineWrapsWhenOnlyOccurrenceAlreadyPassedToday() {
        let store = makeStore()
        // Only a Monday 07:00 routine; it's Monday 09:00 (already passed). The next occurrence
        // is the same routine next Monday — it must still surface, not return nil.
        let routine = run("Early", at: ScheduleTime(hour: 7, minute: 0), days: [.monday])
        store.add(routine)
        let next = store.nextRoutine(fromWeekday: .monday, hour: 9, minute: 0)
        #expect(next?.name == "Early")
    }

    @Test func corruptFileIsPreservedAndStoreStartsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routines-corrupt-\(UUID().uuidString).json")
        try Data("{ not valid json".utf8).write(to: url)

        let store = RoutineStore(fileURL: url)
        #expect(store.routines.isEmpty) // didn't crash, started clean

        // The unreadable file was preserved as a sidecar rather than silently destroyed.
        let backup = url.appendingPathExtension("corrupt")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func nextOccurrencePicksSoonestAcrossRoutines() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: now)!
        let wdTomorrow = DayOfWeek(rawValue: cal.component(.weekday, from: tomorrow))!
        let wdDayAfter = DayOfWeek(rawValue: cal.component(.weekday, from: dayAfter))!

        let store = makeStore()
        store.add(run("Sooner", at: ScheduleTime(hour: 6, minute: 0), days: [wdTomorrow]))
        store.add(run("Later", at: ScheduleTime(hour: 6, minute: 0), days: [wdDayAfter]))

        let next = store.nextOccurrence(now: now, calendar: cal)
        #expect(next?.routine.name == "Sooner")
        #expect(next?.date == cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6)))
    }

    @Test func nextOccurrenceKeepsPassedTimeTodayUntilDayEnd() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let today = DayOfWeek(rawValue: cal.component(.weekday, from: now))!

        let store = makeStore()
        store.add(run("Earlier today", at: ScheduleTime(hour: 6, minute: 0), days: [today]))
        let next = store.nextOccurrence(now: now, calendar: cal)
        // 06:00 already passed today, but the workout is still today's — it stays up next
        // (dated earlier today) until the day ends, rather than vanishing to next week.
        #expect(next?.date == cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 6)))
        #expect(next?.hasTime == true)
    }

    @Test func nextOccurrenceRollsToNextWeekOnceTheDayEnds() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // Just past midnight the day after the June 15 06:00 occurrence.
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 0, minute: 5))!
        let monday = DayOfWeek(rawValue: cal.component(.weekday, from: cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!))!

        let store = makeStore()
        store.add(run("Monday run", at: ScheduleTime(hour: 6, minute: 0), days: [monday]))
        let next = store.nextOccurrence(now: now, calendar: cal)
        #expect(next?.date == cal.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 6)))
    }

    @Test func nextOccurrenceTimelessRoutineIsAllDayTodayWithNoFabricatedTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let today = DayOfWeek(rawValue: cal.component(.weekday, from: now))!

        let store = makeStore()
        store.add(run("Anytime", at: nil, days: [today]))
        let next = store.nextOccurrence(now: now, calendar: cal)
        // A day-only routine occurs all day: today at start-of-day, flagged time-less so no
        // caller can render "12:00 AM" from the midnight placeholder.
        #expect(next?.date == cal.startOfDay(for: now))
        #expect(next?.hasTime == false)
    }

    @Test func nextOccurrenceNilWhenNoRoutines() {
        let store = makeStore()
        #expect(store.nextOccurrence() == nil)
    }

    @Test func missingFileStartsEmptyWithoutBackup() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routines-missing-\(UUID().uuidString).json")
        let store = RoutineStore(fileURL: url)
        #expect(store.routines.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }
}
