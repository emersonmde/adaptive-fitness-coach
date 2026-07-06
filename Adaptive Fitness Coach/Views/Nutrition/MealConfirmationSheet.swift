import SwiftUI
import AdaptiveCore

/// The whole capture→confirm flow's one surface (build 10). Presents the moment identify
/// starts (progress), becomes the confirmation screen (spec §4.3), and holds identify
/// failures honestly with a retry — the user never watches a screen close into silence.
///
/// Confirmation shows each item's number and its source *before* Log (lookups start when the
/// screen opens, sequentially), and the calorie value is editable inline — an override is the
/// user's number (`.userStated`), same semantics as the day screen's post-hoc edit. §5's
/// rule survives: unchecked items still never spend a lookup.
struct MealConfirmationSheet: View {
    @Bindable var controller: MealLogController
    /// Set ONLY when this flow was opened from a watch quick-log review card: deletes the
    /// pending row for good. Cancel deliberately keeps the row ("not now"); without this,
    /// a mistaken dictation's only in-sheet exit re-parked it forever (the card's
    /// long-press dismiss exists but wasn't being discovered).
    var onDiscardReview: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                switch controller.phase {
                case .identifying:
                    identifyingView
                case .failed:
                    failedView
                default:
                    if let draft = controller.draft {
                        confirmationList(draft)
                    } else {
                        // A presented sheet must never be a dark void — if the draft is
                        // momentarily nil in a non-identifying phase, keep the progress
                        // treatment up rather than showing bare background.
                        identifyingView
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
                if onDiscardReview != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            confirmingDiscard = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete this watch log")
                        .accessibilityIdentifier("meal.confirm.discardReview")
                    }
                }
            }
            .confirmationDialog("Delete this watch log?", isPresented: $confirmingDiscard,
                                titleVisibility: .visible) {
                Button("Delete — don't save", role: .destructive) {
                    onDiscardReview?()
                }
            } message: {
                Text("Nothing will be saved to Health. Cancel keeps it waiting instead.")
            }
        }
        .interactiveDismissDisabled()   // Cancel is explicit; a swipe shouldn't silently drop edits
    }

    // MARK: - Identifying (the previously-invisible gap)

    private var identifyingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Reading your meal…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("meal.confirm.identifying")
        }
    }

    // MARK: - Identify failed (honest, retryable — principle 13)

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Theme.textTertiary)
            Text(controller.error ?? "Couldn't read that capture.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("meal.confirm.failedError")
            PrimaryButton(title: "Try Again", systemImage: "arrow.counterclockwise") {
                Task { await controller.retryCapture() }
            }
            .accessibilityIdentifier("meal.confirm.retry")
        }
        .padding(24)
    }

    // MARK: - Confirmation

    private func confirmationList(_ draft: MealDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(draft)
                VStack(spacing: 10) {
                    ForEach(draft.items) { item in
                        ItemRow(
                            item: item,
                            nutrition: controller.displayedNutrition(for: item.id),
                            onToggle: { controller.toggleItem(item.id) },
                            onRename: { controller.editItemName(item.id, name: $0) },
                            onQuantity: { controller.setQuantity(item.id, quantity: $0) },
                            onAnswer: { controller.answer($0, itemID: item.id) },
                            onCalories: { controller.setCalories(item.id, kcal: $0) }
                        )
                    }
                }
                // The when-row (build 8): meal chips + day control, prefilled
                // from the capture when it carried a date (labeled honestly).
                WhenRow(
                    mealSlot: Binding(
                        get: { controller.mealSlot },
                        set: { controller.setMealSlot($0) }
                    ),
                    date: Binding(
                        get: { controller.loggedDate },
                        set: { controller.setLoggedDate($0) }
                    ),
                    prefillCaption: controller.prefilledFromCapture
                        ? "From the capture · " + controller.loggedDate
                            .formatted(.dateTime.month(.abbreviated).day().hour().minute())
                        : nil
                )
                .padding(.top, 2)

            }
            .padding(16)
        }
        // The commit bar is PINNED: on a six-item receipt the total and Log scrolled away,
        // killing the check-an-item → total-updates feedback loop and the fast path alike.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack {
                    if lookingUpCount(draft) > 0 {
                        Text("Looking up \(lookingUpCount(draft))…")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let total = totalText(draft) {
                        Text(total)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("meal.confirm.total")
                    }
                }
                .frame(height: 18)   // reserved slot — no jump when the total lands
                if let error = controller.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.hot)
                        .accessibilityIdentifier("meal.confirm.error")
                }
                // Stable label (a CTA is not a message board — the rows say why it's off);
                // disabled while any checked item is still looking up: never commit a
                // number the screen hasn't shown (the resolver's bottom rung guarantees
                // every lookup ends, so this can't wedge).
                PrimaryButton(
                    title: checkedCount(draft) == 1 ? "Log 1 item" : "Log \(checkedCount(draft)) items",
                    systemImage: "checkmark"
                ) {
                    Task {
                        await controller.commit()
                        if controller.phase != .confirming {
                            Theme.Haptics.success()   // the log landed
                            dismiss()
                        }
                    }
                }
                .disabled(checkedCount(draft) == 0 || lookingUpCount(draft) > 0)
                .accessibilityIdentifier("meal.confirm.log")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
    }

    private func lookingUpCount(_ draft: MealDraft) -> Int {
        draft.items.filter { $0.isChecked && controller.displayedNutrition(for: $0.id) == nil }.count
    }

    private func checkedCount(_ draft: MealDraft) -> Int {
        draft.items.filter(\.isChecked).count
    }

    /// The running day-impact of what's checked — shown once every checked item has a
    /// number ("≈" whenever any of them is an estimate range). Nothing while lookups run:
    /// a partial sum reads as a final one.
    private func totalText(_ draft: MealDraft) -> String? {
        let checked = draft.items.filter(\.isChecked)
        guard !checked.isEmpty else { return nil }
        var total = 0.0
        var approximate = false
        for item in checked {
            guard let nutrition = controller.displayedNutrition(for: item.id) else { return nil }
            total += nutrition.facts.energy.midpointKcal * Double(item.quantity)
            if nutrition.facts.energy.isRange { approximate = true }
        }
        return "Total \(approximate ? "≈ " : "")\(Int(total.rounded()).formatted()) kcal"
    }

    private func header(_ draft: MealDraft) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: draft.classification))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)   // decorative — the header text names the kind
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
        case .typed: "typed"
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
        case .typed: "keyboard"
        }
    }
}

// MARK: - Row

private struct ItemRow: View {
    let item: DraftItem
    let nutrition: ResolvedNutrition?
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onQuantity: (Int) -> Void
    let onAnswer: (QuestionAnswer) -> Void
    let onCalories: (Double) -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var isEditingKcal = false
    @State private var draftKcal = ""
    @FocusState private var kcalFocused: Bool

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
                    .accessibilityLabel("Include \(item.name)")
                    .accessibilityValue(item.isChecked ? "included" : "excluded")
                    .accessibilityAddTraits(.isToggle)

                    if isEditing {
                        TextField("Item name", text: $draftName)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(commitRename)
                            .accessibilityIdentifier("meal.confirm.nameField")
                    } else {
                        // Same quiet pencil the kcal line carries — a misread name is the
                        // most common fix, and an affordance-free tap target is invisible
                        // to exactly the user who needs it (§4.3).
                        HStack(spacing: 5) {
                            Text(item.name)
                                .font(.body)
                                .foregroundStyle(item.isChecked ? Theme.textPrimary : Theme.textTertiary)
                                .strikethrough(!item.isChecked, color: Theme.textTertiary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .onTapGesture(perform: beginRename)
                        // A tap gesture on a plain view is invisible to VoiceOver —
                        // expose the rename as the button it behaves like.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Rename \(item.name)")
                        .accessibilityAddTraits(.isButton)
                    }

                    Spacer(minLength: 8)

                    // Reserved slot (principle 7): hidden-not-removed when unchecked, so
                    // toggling a row never shifts the layout.
                    quantityControl
                        .opacity(item.isChecked || item.quantity > 1 ? 1 : 0)
                        .disabled(!item.isChecked && item.quantity <= 1)
                }
                if item.isChecked {
                    nutritionLine
                }
                // A stated override outranks everything a re-lookup could produce, so the
                // chips would be inert theater once the user has typed their own number.
                if item.isChecked, item.statedFacts == nil, let question = item.question {
                    QuestionnaireOptionRow(question: question, onAnswer: onAnswer)
                }
            }
        }
        .opacity(item.isChecked ? 1 : 0.65)
        // Tapping away is as common as tapping Done: commit whatever was typed when focus
        // leaves an inline editor, so no edit is silently stranded in a stuck field.
        .onChange(of: nameFocused) {
            if !nameFocused, isEditing { commitRename() }
        }
        .onChange(of: kcalFocused) {
            if !kcalFocused, isEditingKcal { commitKcal() }
        }
    }

    // MARK: The number + its source, pre-commit (build 10)

    /// "460 kcal · Open Food Facts", "350–600 kcal · estimate", "520 kcal · your number" —
    /// or an honest "Looking up…" while the ladder runs. Tapping the number edits it.
    @ViewBuilder
    private var nutritionLine: some View {
        if isEditingKcal {
            HStack(spacing: 6) {
                TextField("kcal", text: $draftKcal)
                    .keyboardType(.numberPad)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .focused($kcalFocused)
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    .submitLabel(.done)
                    .onSubmit(commitKcal)
                    .accessibilityIdentifier("meal.confirm.kcalField")
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Button("Done", action: commitKcal)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("meal.confirm.kcalDone")
                Spacer()
            }
            .padding(.leading, 34)   // aligns under the name, past the checkbox
        } else if let nutrition {
            Button(action: beginKcalEdit) {
                HStack(spacing: 5) {
                    Text(energyText(nutrition))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    // Provenance is a load-bearing honesty string (C3) — secondary, not
                    // tertiary: the app's lowest-contrast text is no place for "where this
                    // number came from".
                    Text("· \(sourceText(nutrition.provenance))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 34)
            .accessibilityIdentifier("meal.confirm.kcal.\(item.name)")
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Looking up…")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.leading, 34)
            .accessibilityIdentifier("meal.confirm.lookingUp.\(item.name)")
        }
    }

    private func energyText(_ nutrition: ResolvedNutrition) -> String {
        let each = item.quantity > 1 ? " each" : ""
        switch nutrition.facts.energy {
        case .exact(let kcal):
            return "\(Int(kcal.rounded())) kcal\(each)"
        case .range(let low, let high):
            return "\(Int(low.rounded()))–\(Int(high.rounded())) kcal\(each)"
        }
    }

    /// Where the number came from (C3), quiet but always present: the seller's own site,
    /// the database's name, an estimate, or the user's number.
    private func sourceText(_ provenance: Provenance) -> String {
        provenance.detailLabel
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

    private func beginKcalEdit() {
        draftKcal = nutrition.map { String(Int($0.facts.energy.midpointKcal.rounded())) } ?? ""
        isEditingKcal = true
        kcalFocused = true
    }

    private func commitKcal() {
        if let kcal = Double(draftKcal.trimmingCharacters(in: .whitespaces)), kcal > 0 {
            onCalories(kcal)
        }
        isEditingKcal = false
    }
}
