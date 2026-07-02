import SwiftUI
import AdaptiveCore

/// A row of seven toggleable day pills (Mon–Sun), used when creating/editing a routine.
struct DayPicker: View {
    @Binding var selection: Set<DayOfWeek>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DayOfWeek.localeWeekOrder, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Theme.accent : Theme.surface2,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                        .shadow(color: Theme.accent.opacity(isOn && !reduceMotion ? 0.15 : 0), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityValue(isOn ? "Selected" : "Not selected")
            }
        }
    }
}

