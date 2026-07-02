import Foundation
import EventKit
import AdaptiveCore

/// Mirrors a routine's schedule to the user's Calendar as a single recurring event.
///
/// Replaces the old local-notification reminder: the user asked for the schedule to appear in
/// their Calendar at the chosen time. One `EKEvent` per routine, repeating weekly on the chosen
/// days with an alert at the start. The event identifier is kept in `UserDefaults` (keyed by
/// routine id) so later edits *update* the same event and deletions remove it.
///
/// Full access is required (not write-only): updating and deleting an existing event both need to
/// fetch it by identifier, which write-only access forbids — without it, edits would pile up
/// duplicate events.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private let mapKey = "routineCalendarEventIDs"

    /// routineID(uuidString) -> EKEvent.eventIdentifier
    private var eventIDs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: mapKey) }
    }

    // MARK: - Access

    /// Whether the app already has full calendar access (no prompt).
    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Ensure full access. When `prompt` is true and status is undetermined, request it; otherwise
    /// only report the current grant (used at launch so we never prompt unsolicited).
    @discardableResult
    func ensureAccess(prompt: Bool) async -> Bool {
        if hasFullAccess { return true }
        guard prompt, EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - Sync

    /// Create / update / delete this routine's calendar event to match its current state.
    /// `prompt` requests access if needed (true when the user just enabled it).
    func sync(for routine: Routine, prompt: Bool = false) async {
        let wantsEvent = routine.reminderEnabled
            && routine.scheduleTime != nil
            && !routine.repeatDays.isEmpty

        guard wantsEvent else { remove(routineID: routine.id); return }
        guard await ensureAccess(prompt: prompt) else { return }

        let event = existingEvent(for: routine.id) ?? EKEvent(eventStore: store)
        apply(routine, to: event)
        do {
            try store.save(event, span: .futureEvents, commit: true)
            var map = eventIDs
            map[routine.id.uuidString] = event.eventIdentifier
            eventIDs = map
        } catch {
            // Non-fatal: the routine is still saved; the calendar just won't reflect it.
        }
    }

    /// Re-sync every routine *without prompting* (launch path) — only events for already-granted
    /// access are touched.
    func syncAll(_ routines: [Routine]) async {
        guard hasFullAccess else { return }
        for routine in routines { await sync(for: routine, prompt: false) }
    }

    /// Remove a routine's event (toggle off or routine deleted).
    func remove(routineID: Routine.ID) {
        guard hasFullAccess, let event = existingEvent(for: routineID) else {
            // Still drop a stale mapping so we don't leak identifiers.
            var map = eventIDs; map[routineID.uuidString] = nil; eventIDs = map
            return
        }
        try? store.remove(event, span: .futureEvents, commit: true)
        var map = eventIDs; map[routineID.uuidString] = nil; eventIDs = map
    }

    // MARK: - Building

    private func existingEvent(for routineID: Routine.ID) -> EKEvent? {
        guard let id = eventIDs[routineID.uuidString] else { return nil }
        return store.event(withIdentifier: id)
    }

    /// Populate an event from the routine: title, next start, duration, weekly recurrence, alarm.
    ///
    /// The series is **re-anchored only when the schedule actually changed** (or the event is
    /// new). Saving with `.futureEvents` from a moved `startDate` erases past occurrences of
    /// the series, so the launch-path `syncAll` must never re-anchor an unchanged event —
    /// otherwise the user's calendar history quietly evaporates one launch at a time.
    private func apply(_ routine: Routine, to event: EKEvent) {
        event.title = routine.name
        event.calendar = event.calendar ?? store.defaultCalendarForNewEvents

        let needsAnchor = event.startDate == nil || !schedule(of: event, matches: routine)
        if needsAnchor, let start = nextStart(for: routine) {
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(routine.estimatedMinutes * 60))
            // Replace any prior recurrence so an edit doesn't accumulate rules.
            (event.recurrenceRules ?? []).forEach { event.removeRecurrenceRule($0) }
            let days = routine.repeatDays
                .sorted()
                .map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0.rawValue)!) }
            event.addRecurrenceRule(EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1,
                daysOfTheWeek: days,
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil
            ))
        } else if let start = event.startDate {
            // Schedule unchanged: keep the anchor (and the series' past), refresh duration only.
            event.endDate = start.addingTimeInterval(TimeInterval(routine.estimatedMinutes * 60))
        }
        event.alarms = [EKAlarm(relativeOffset: 0)]
    }

    /// Whether the event's existing series already encodes the routine's schedule
    /// (same time of day, same weekly recurrence days).
    private func schedule(of event: EKEvent, matches routine: Routine, calendar: Calendar = .current) -> Bool {
        guard let start = event.startDate, let time = routine.scheduleTime else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: start)
        guard comps.hour == time.hour, comps.minute == time.minute else { return false }
        let ruleDays = Set((event.recurrenceRules?.first?.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
        return ruleDays == Set(routine.repeatDays.map(\.rawValue))
    }

    /// The soonest upcoming start among the routine's days at its scheduled time — anchors the
    /// recurring series.
    private func nextStart(for routine: Routine, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let time = routine.scheduleTime else { return nil }
        return routine.repeatDays.compactMap { day -> Date? in
            var c = DateComponents()
            c.weekday = day.rawValue
            c.hour = time.hour
            c.minute = time.minute
            return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}
