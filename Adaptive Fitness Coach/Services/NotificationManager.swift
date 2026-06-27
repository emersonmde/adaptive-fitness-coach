import Foundation
import UserNotifications
import AdaptiveCore

/// Schedules the per-routine reminders that launch a workout on the watch.
///
/// Each routine produces one repeating local notification per repeat-day, carrying the
/// routine id so a tap can deep-link straight to that session. Reminders are the only thing
/// that "launches" a workout in P0 — tapping one (on the watch mirror) opens the watch app
/// at the launch screen for that routine.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// Notification category for workout reminders; actions/deep-link key off this.
    static let reminderCategory = "WORKOUT_REMINDER"
    /// `userInfo` key holding the routine id (UUID string).
    static let routineIDKey = "routineID"

    private let center = UNUserNotificationCenter.current()

    /// Ask for permission to post reminders. Returns whether it was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Identifier for a routine's notification on a specific weekday.
    private func identifier(routineID: UUID, day: DayOfWeek) -> String {
        "routine-\(routineID.uuidString)-\(day.rawValue)"
    }

    /// Replace all reminders for a routine to match its current schedule. Cancels first so
    /// edits (changed days/time, reminders off) never leave stale notifications behind.
    func reschedule(for routine: Routine) {
        cancel(routineID: routine.id)

        guard routine.reminderEnabled, let time = routine.scheduleTime else { return }

        for day in routine.repeatDays {
            let content = UNMutableNotificationContent()
            content.title = routine.name
            content.body = "Time for your \(routine.type.displayName). Tap to start on your Apple Watch."
            content.sound = .default
            content.categoryIdentifier = Self.reminderCategory
            content.userInfo = [Self.routineIDKey: routine.id.uuidString]

            var components = DateComponents()
            components.weekday = day.rawValue
            components.hour = time.hour
            components.minute = time.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: identifier(routineID: routine.id, day: day),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    /// Cancel every pending reminder for a routine across all weekdays.
    func cancel(routineID: UUID) {
        let ids = DayOfWeek.allCases.map { identifier(routineID: routineID, day: $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Re-sync reminders for the full routine set (e.g. on launch).
    func rescheduleAll(_ routines: [Routine]) {
        for routine in routines { reschedule(for: routine) }
    }
}
