import Foundation

/// Which meal of the day an entry belongs to — the Food screen's grouping axis.
/// Always auto-suggested from the clock (C1: a sensible default, never a required question);
/// a chip on the confirmation/edit sheets lets the user correct it.
public enum MealSlot: String, Sendable, Codable, CaseIterable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack

    /// Hour-of-day assignment. Boundaries are deliberately generous: 4–10 breakfast,
    /// 11–15 lunch, 16–20 dinner, everything else (21:00–03:59) a snack — late-night food is
    /// a snack, not tomorrow's breakfast.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case 4...10: .breakfast
        case 11...15: .lunch
        case 16...20: .dinner
        default: .snack
        }
    }

    public var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// Stable presentation order for the day screen's sections.
    public static let dayOrder: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]
}
