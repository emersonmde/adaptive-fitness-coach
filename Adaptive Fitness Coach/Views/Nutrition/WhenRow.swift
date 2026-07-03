import SwiftUI
import AdaptiveCore

/// The "when" of an entry: meal chips + a day control. Shared by the confirmation sheet and
/// the edit sheet. Fixed height, no layout jumps (principle 7): the inline date picker lives
/// in a disclosure that grows the sheet, not the row.
struct WhenRow: View {
    @Binding var mealSlot: MealSlot
    @Binding var date: Date
    /// e.g. "From receipt · Jul 1, 6:42 PM" — shown quietly when the capture supplied the date.
    var prefillCaption: String?
    var onSlotChange: ((MealSlot) -> Void)?
    var onDateChange: ((Date) -> Void)?

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prefillCaption {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption2)
                    Text(prefillCaption)
                        .font(.caption2)
                        .accessibilityIdentifier("meal.when.prefill")
                }
                .foregroundStyle(Theme.textTertiary)
            }

            // Meal chips — auto-defaulted, one tap to correct (C1).
            HStack(spacing: 8) {
                ForEach(MealSlot.dayOrder, id: \.self) { slot in
                    chip(slot.displayName, selected: mealSlot == slot, id: "meal.when.slot.\(slot.rawValue)") {
                        mealSlot = slot
                        onSlotChange?(slot)
                    }
                }
            }

            // Day control: Today (default weightless) · Yesterday · Other…
            HStack(spacing: 8) {
                chip("Today", selected: isToday, id: "meal.when.today") {
                    set(dayOffset: 0)
                }
                chip("Yesterday", selected: isYesterday, id: "meal.when.yesterday") {
                    set(dayOffset: -1)
                }
                chip(otherLabel, selected: !isToday && !isYesterday, id: "meal.when.other") {
                    showingPicker.toggle()
                }
                Spacer()
            }

            if showingPicker {
                DatePicker(
                    "Logged",
                    selection: Binding(
                        get: { date },
                        set: { newValue in
                            date = min(newValue, Date())
                            onDateChange?(date)
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Theme.accent)
            }
        }
    }

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isYesterday: Bool { calendar.isDateInYesterday(date) }

    private var otherLabel: String {
        if isToday || isYesterday { return "Other…" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Keep the time-of-day when hopping whole days (a 6pm receipt stays a 6pm entry).
    private func set(dayOffset: Int) {
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let combined = calendar.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: targetDay
        ) ?? targetDay
        date = min(combined, Date())
        showingPicker = false
        onDateChange?(date)
    }

    private func chip(_ label: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.accent : Theme.surface2))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline))
        }
        .accessibilityIdentifier(id)
    }
}
