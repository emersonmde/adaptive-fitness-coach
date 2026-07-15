import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// The done-today marker behind the launch screens' receipt state (W22): completions record
/// per routine, "today" is a calendar-day question, and the "Next: Thu" label comes from pure
/// weekday math over the routine's repeat days.
struct LastCompletionStoreTests {

    /// A throwaway defaults suite per test — never the app's real standard defaults.
    private func makeDefaults() -> UserDefaults {
        let name = "LastCompletionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func completionRecordsAndReadsBackSameDay() {
        let defaults = makeDefaults()
        let store = LastCompletionStore(defaults: defaults)
        let id = UUID()
        #expect(!store.completedToday(routineId: id))
        store.recordCompletion(routineId: id)
        #expect(store.completedToday(routineId: id))
        // Another routine's marker never bleeds over.
        #expect(!store.completedToday(routineId: UUID()))
    }

    @Test func yesterdaysCompletionIsNotToday() {
        let defaults = makeDefaults()
        let id = UUID()
        // Record "yesterday" by injecting a now 25h in the past, then read with a real now.
        let yesterday = Date().addingTimeInterval(-25 * 3600)
        LastCompletionStore(defaults: defaults, now: { yesterday }).recordCompletion(routineId: id)
        #expect(!LastCompletionStore(defaults: defaults).completedToday(routineId: id))
    }

    @Test func latestCompletionWinsPerRoutine() {
        let defaults = makeDefaults()
        let id = UUID()
        let yesterday = Date().addingTimeInterval(-25 * 3600)
        LastCompletionStore(defaults: defaults, now: { yesterday }).recordCompletion(routineId: id)
        LastCompletionStore(defaults: defaults).recordCompletion(routineId: id)
        #expect(LastCompletionStore(defaults: defaults).completedToday(routineId: id))
    }

    // MARK: - Next-day label (pure weekday math)

    /// A fixed Wednesday for deterministic weekday offsets.
    private var wednesday: Date {
        // 2026-07-15 is a Wednesday.
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 15; components.hour = 9
        return Calendar.current.date(from: components)!
    }

    @Test func nextDayLabelSkipsTodayAndFindsTheNextRepeatDay() {
        // Wed → next repeat day among Mon/Thu is Thursday, tomorrow.
        let label = LastCompletionStore.nextDayLabel(
            repeatDays: [.monday, .thursday], after: wednesday)
        #expect(label == "Tomorrow")
    }

    @Test func nextDayLabelNamesADayLaterThisWeek() {
        // Wed → next among Mon/Sat is Saturday.
        let label = LastCompletionStore.nextDayLabel(
            repeatDays: [.monday, .saturday], after: wednesday)
        #expect(label == "Sat")
    }

    @Test func nextDayLabelWrapsToNextWeekSameDay() {
        // Wed with only Wednesday scheduled → the next occurrence is a full week out.
        let label = LastCompletionStore.nextDayLabel(repeatDays: [.wednesday], after: wednesday)
        #expect(label == "next Wed")
    }

    @Test func noRepeatDaysMeansNoFabricatedLabel() {
        // N6: an unscheduled routine gets silence, never an invented "Next".
        #expect(LastCompletionStore.nextDayLabel(repeatDays: [], after: wednesday) == nil)
    }
}
