import SwiftUI
import AdaptiveCore

/// The confirmation screen (spec §4.3): identified items with checkboxes, inline name fixes,
/// quantity, and C4's tap-only clarifying chips — then one button, **Log**. No calorie numbers
/// here: lookups run *after* commit (C2/§5 — never spend lookups on unchecked items), so this
/// screen never has to show a number it would later contradict.
struct MealConfirmationSheet: View {
    @Bindable var controller: MealLogController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let draft = controller.draft {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(draft)
                            VStack(spacing: 10) {
                                ForEach(draft.items) { item in
                                    ItemRow(
                                        item: item,
                                        onToggle: { controller.toggleItem(item.id) },
                                        onRename: { controller.editItemName(item.id, name: $0) },
                                        onQuantity: { controller.setQuantity(item.id, quantity: $0) },
                                        onAnswer: { controller.answer($0, itemID: item.id) }
                                    )
                                }
                            }
                            if let error = controller.error {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.hot)
                                    .accessibilityIdentifier("meal.confirm.error")
                            }
                            PrimaryButton(
                                title: checkedCount(draft) == 0 ? "Nothing selected" : "Log \(checkedCount(draft)) item\(checkedCount(draft) == 1 ? "" : "s")",
                                systemImage: "checkmark"
                            ) {
                                Task {
                                    await controller.commit()
                                    if controller.phase != .confirming { dismiss() }
                                }
                            }
                            .disabled(checkedCount(draft) == 0)
                            .accessibilityIdentifier("meal.confirm.log")
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("meal.confirm.cancel")
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()   // Cancel is explicit; a swipe shouldn't silently drop edits
    }

    private func checkedCount(_ draft: MealDraft) -> Int {
        draft.items.filter(\.isChecked).count
    }

    private func header(_ draft: MealDraft) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: draft.classification))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(headerText(draft))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("meal.confirm.header")
        }
    }

    private func headerText(_ draft: MealDraft) -> String {
        let kind = switch draft.classification {
        case .barcode: "barcode"
        case .receipt: "receipt"
        case .nutritionLabel: "nutrition label"
        case .plate: "photo"
        case .unknown: "capture"
        }
        if let seller = draft.seller { return "\(seller.name) · \(kind)" }
        return kind.prefix(1).uppercased() + kind.dropFirst()
    }

    private func icon(for classification: CaptureClassification) -> String {
        switch classification {
        case .barcode: "barcode"
        case .receipt: "doc.text"
        case .nutritionLabel: "tablecells"
        case .plate: "fork.knife"
        case .unknown: "questionmark.circle"
        }
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: DraftItem
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onQuantity: (Int) -> Void
    let onAnswer: (QuestionAnswer) -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: onToggle) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isChecked ? Theme.accent : Theme.textTertiary)
                    }
                    .accessibilityIdentifier("meal.confirm.check.\(item.name)")

                    if isEditing {
                        TextField("Item name", text: $draftName)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(commitRename)
                            .accessibilityIdentifier("meal.confirm.nameField")
                    } else {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(item.isChecked ? Theme.textPrimary : Theme.textTertiary)
                            .strikethrough(!item.isChecked, color: Theme.textTertiary)
                            .onTapGesture(perform: beginRename)   // fix a misread inline (§4.3)
                    }

                    Spacer(minLength: 8)

                    if item.quantity > 1 || item.isChecked {
                        quantityControl
                    }
                }
                if item.isChecked, let question = item.question {
                    QuestionnaireOptionRow(question: question, onAnswer: onAnswer)
                }
            }
        }
        .opacity(item.isChecked ? 1 : 0.65)
    }

    private var quantityControl: some View {
        HStack(spacing: 8) {
            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Stepper("Quantity", value: Binding(get: { item.quantity }, set: onQuantity), in: 1...20)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func beginRename() {
        draftName = item.name
        isEditing = true
        nameFocused = true
    }

    private func commitRename() {
        onRename(draftName)
        isEditing = false
    }
}
