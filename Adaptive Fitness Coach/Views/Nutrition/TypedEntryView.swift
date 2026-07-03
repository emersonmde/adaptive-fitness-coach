import SwiftUI
import AdaptiveCore

/// The typed/dictated entry sheet: one autofocused field, one Add. The text flows through the
/// exact same identify → confirm → ladder pipeline as a camera capture — stated calories
/// ("…, 650 calories") and date words ("last night") are honored by the deterministic parsers.
struct TypedEntryView: View {
    let onSubmit: (MealCapture) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    TextField("e.g. chicken burrito, 650 calories", text: $text, axis: .vertical)
                        .focused($focused)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(submit)
                        .padding(14)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("meal.typed.field")

                    Text("Say what it was — a stated calorie count or \"yesterday\" is understood.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    PrimaryButton(title: "Add", systemImage: "plus") { submit() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("meal.typed.submit")

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Type a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        onSubmit(MealCapture(typedText: trimmed))
    }
}
