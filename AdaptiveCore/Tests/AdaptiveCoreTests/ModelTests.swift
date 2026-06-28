import Foundation
import Testing
@testable import AdaptiveCore

struct ModelTests {

    // MARK: - beginnerRunWalk factory

    @Test func beginnerRunWalkHasExpectedStructure() {
        let plan = IntervalPlan.beginnerRunWalk()
        // 1 warmup + (8 * 2) run/walk + 1 cooldown = 18 segments
        #expect(plan.segments.count == 18)
        #expect(plan.segments.first?.phase == .warmupWalk)
        #expect(plan.segments.last?.phase == .cooldownWalk)
        #expect(plan.runIntervalCount == 8)
    }

    @Test func beginnerRunWalkPlannedDuration() {
        let plan = IntervalPlan.beginnerRunWalk()
        // 300 warmup + 8*(60+90) + 300 cooldown = 300 + 1200 + 300 = 1800s
        #expect(plan.plannedDuration == 1800)
    }

    @Test func beginnerRunWalkAlternatesRunAndWalk() {
        let plan = IntervalPlan.beginnerRunWalk()
        let middle = plan.segments[1..<(plan.segments.count - 1)]
        for (offset, segment) in middle.enumerated() {
            // even offsets are runs, odd are walks
            #expect(segment.phase == (offset.isMultiple(of: 2) ? .run : .walk))
        }
    }

    @Test func beginnerRunWalkCustomParameters() {
        let plan = IntervalPlan.beginnerRunWalk(
            warmup: 60, runDuration: 30, walkDuration: 60, cycles: 2, cooldown: 60
        )
        #expect(plan.segments.count == 6) // 1 + 2*2 + 1
        #expect(plan.runIntervalCount == 2)
        #expect(plan.plannedDuration == 60 + 2 * (30 + 60) + 60)
    }

    // MARK: - DayOfWeek

    @Test func dayOfWeekMatchesCalendarNumbering() {
        // Calendar uses Sunday = 1 ... Saturday = 7
        #expect(DayOfWeek.sunday.rawValue == 1)
        #expect(DayOfWeek.saturday.rawValue == 7)
    }

    @Test func dayOfWeekSortsChronologically() {
        let shuffled: [DayOfWeek] = [.friday, .monday, .wednesday, .sunday]
        #expect(shuffled.sorted() == [.sunday, .monday, .wednesday, .friday])
    }

    @Test func orderedWeekRespectsFirstWeekday() {
        // US locale (Sunday-first, firstWeekday == 1) — like the Alarm/Calendar apps.
        let sundayFirst = DayOfWeek.orderedWeek(firstWeekday: 1)
        #expect(sundayFirst == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        // Monday-first locales (firstWeekday == 2).
        let mondayFirst = DayOfWeek.orderedWeek(firstWeekday: 2)
        #expect(mondayFirst.first == .monday)
        #expect(mondayFirst.last == .sunday)
        #expect(mondayFirst.count == 7)
        // Wraps correctly from any start (Saturday-first, firstWeekday == 7).
        #expect(DayOfWeek.orderedWeek(firstWeekday: 7).first == .saturday)
        #expect(DayOfWeek.orderedWeek(firstWeekday: 7) == [.saturday, .sunday, .monday, .tuesday, .wednesday, .thursday, .friday])
    }

    // MARK: - Codable round-trips

    @Test func routineRoundTrips() throws {
        let routine = Routine(
            name: "Morning Run",
            type: .adaptiveRun,
            repeatDays: [.monday, .thursday],
            scheduleTime: ScheduleTime(hour: 7, minute: 0),
            reminderEnabled: true
        )
        let data = try JSONEncoder().encode(routine)
        let decoded = try JSONDecoder().decode(Routine.self, from: data)
        #expect(decoded == routine)
    }

    @Test func intervalPlanRoundTrips() throws {
        let plan = IntervalPlan.beginnerRunWalk()
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(IntervalPlan.self, from: data)
        #expect(decoded == plan)
    }

    @Test func durationRoundTripsAndDefaultsForLegacyData() throws {
        // Present value survives a round-trip.
        let routine = Routine(name: "Tempo", type: .adaptiveRun, durationMinutes: 45)
        let decoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(routine))
        #expect(decoded.durationMinutes == 45)

        // A routine persisted before `durationMinutes` existed (build 2) decodes with the default,
        // not a failure. Simulate by stripping the key from otherwise-valid JSON.
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(routine)) as! [String: Any]
        dict.removeValue(forKey: "durationMinutes")
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let legacyDecoded = try JSONDecoder().decode(Routine.self, from: legacy)
        #expect(legacyDecoded.durationMinutes == 30)
    }

    @Test func scaledPlanTracksTargetDuration() {
        for minutes in [10, 20, 30, 45, 60] {
            let total = TimeInterval(minutes * 60)
            let plan = IntervalPlan.beginnerRunWalk(totalDuration: total)
            #expect(plan.runIntervalCount >= 1)                 // never a runless run
            // Lands within one run/walk cycle (150s) of the requested length — it's a seed.
            #expect(abs(plan.plannedDuration - total) <= 150)
            // Warmup & cooldown are capped at 5 minutes.
            #expect(plan.segments.first!.targetDuration <= 300)
            #expect(plan.segments.last!.targetDuration <= 300)
        }
    }

    // MARK: - AdaptationEvent copy

    @Test func adaptationMessagesAreDistinct() {
        let actions: [AdaptationAction] = [.shortenedRun, .extendedRun, .lengthenedWalk, .shortenedWalk]
        let messages = actions.map { AdaptationEvent(action: $0, atSessionTime: 0, zone: 3).message }
        #expect(Set(messages).count == actions.count)
    }

    @Test func effortDirectionIsCorrect() {
        #expect(AdaptationAction.extendedRun.increasesEffort)
        #expect(AdaptationAction.shortenedWalk.increasesEffort)
        #expect(!AdaptationAction.shortenedRun.increasesEffort)
        #expect(!AdaptationAction.lengthenedWalk.increasesEffort)
    }

    // MARK: - IntervalPhase semantics

    @Test func phaseRunWalkClassification() {
        #expect(IntervalPhase.run.isRun)
        #expect(!IntervalPhase.run.isWalk)
        for walk in [IntervalPhase.warmupWalk, .walk, .cooldownWalk] {
            #expect(walk.isWalk)
            #expect(!walk.isRun)
        }
    }
}
