import SwiftUI
import AdaptiveCore

/// C4's structured clarification as native UI: one quiet prompt line + tappable option chips,
/// default pre-selected — the Claude Code option-picker spirit. Skipping is free: the default
/// answers itself at commit; tapping just refines.
struct QuestionnaireOptionRow: View {
    let question: ClarifyingQuestion
    let onAnswer: (QuestionAnswer) -> Void

    @State private var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.prompt)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(question.options) { option in
                    chip(option)
                }
            }
        }
    }

    private func chip(_ option: ClarifyingQuestion.Option) -> some View {
        let isSelected = (selectedID ?? question.defaultOptionID) == option.id
        return Button {
            selectedID = option.id
            onAnswer(QuestionAnswer(question: question, option: option))
        } label: {
            Text(option.label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Theme.accent : Theme.surface2)
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline)
                )
        }
        .accessibilityIdentifier("meal.question.\(question.id).\(option.id)")
    }
}
