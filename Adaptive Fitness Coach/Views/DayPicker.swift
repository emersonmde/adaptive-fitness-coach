import SwiftUI
import AdaptiveCore

/// A row of seven toggleable day pills (Mon–Sun), used when creating/editing a routine.
struct DayPicker: View {
    @Binding var selection: Set<DayOfWeek>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DayOfWeek.weekOrder, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Color.accentColor : Color(.secondarySystemFill))
                        .foregroundStyle(isOn ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityValue(isOn ? "Selected" : "Not selected")
            }
        }
    }
}

