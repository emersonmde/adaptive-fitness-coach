import Foundation
import AdaptiveCore

extension ScheduleTime {
    /// Localized short time string (e.g. "7:00 AM") for display in the phone UI.
    var formatted: String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
