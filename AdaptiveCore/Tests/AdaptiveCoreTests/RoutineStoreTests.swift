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

    @Test func nextOccurrenceSkipsPassedTimeTodayToNextWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let today = DayOfWeek(rawValue: cal.component(.weekday, from: now))!

        let store = makeStore()
        store.add(run("Earlier today", at: ScheduleTime(hour: 6, minute: 0), days: [today]))
        let next = store.nextOccurrence(now: now, calendar: cal)
        // 06:00 already passed today → next is the same weekday next week (June 22).
        #expect(next?.date == cal.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 6)))
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
