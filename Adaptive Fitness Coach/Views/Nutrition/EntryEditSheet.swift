import SwiftUI
import UIKit
import AdaptiveCore

/// Edits one logged entry — name, calories, meal, day — then `replace`s it in Health
/// (delete + rewrite; samples are immutable). A changed calorie value honestly becomes
/// "your number" (.userStated); the quiet note appears only when that's about to happen.
/// Failure keeps the sheet open with an honest line — Cancel is always an exit.
struct EntryEditSheet: View {
    let entry: MealEntry
    let recorder: any NutritionRecorder
    let onSaved: () -> Void
    /// "Log again today" recorded a fresh copy — reports the new entry's id so the day
    /// screen can badge exactly that row (and say so when it landed off-screen).
    var onRelogged: ((UUID) -> Void)? = nil

    @State private var name: String
    @State private var kcalText: String
    @State private var quantity: Int
    @State private var mealSlot: MealSlot
    @State private var date: Date
    @State private var error: String?
    @State private var saving = false
    /// A swipe-down (or Cancel) with unsaved edits confirms instead of silently discarding.
    @State private var confirmingDiscard = false
    /// The number becomes "yours" only if you actually touched the field — inferring from
    /// value comparison converted a range estimate to `.userStated` on ANY edit (slot/day),
    /// silently destroying the honest range and its assumptions.
    @State private var kcalEdited = false
    @State private var sellerName: String
    /// "Look up again": the ladder re-run against the edited name/seller. Non-nil means the
    /// save records these facts + provenance (unless the user re-types the kcal afterwards).
    @State private var rescanResult: ResolvedNutrition?
    @State private var rescanning = false
    /// P6 refresh: the other defensible matches the re-lookup saw ("not this one?").
    @State private var alternates: [ResolvedAlternative] = []
    /// Distinguishes the rescan writing the kcal preview from the user typing (only the
    /// latter makes the number "yours").
    @State private var programmaticKcalWrite = false
    @State private var confirmingDelete = false
    /// The lookup ladder, same wiring as the log flow (scripted in the simulator).
    private let resolver = MealPipelineProvider.makeResolver()
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case name, seller, kcal }
    @FocusState private var focusedField: Field?

    init(
        entry: MealEntry,
        recorder: any NutritionRecorder,
        onSaved: @escaping () -> Void,
        onRelogged: ((UUID) -> Void)? = nil
    ) {
        self.entry = entry
        self.recorder = recorder
        self.onSaved = onSaved
        self.onRelogged = onRelogged
        _name = State(initialValue: entry.name)
        _sellerName = State(initialValue: entry.seller?.name ?? "")
        _kcalText = State(initialValue: String(Int(entry.facts.energy.midpointKcal.rounded())))
        _quantity = State(initialValue: entry.quantity)
        _mealSlot = State(initialValue: entry.meal)
        _date = State(initialValue: entry.date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field("NAME") {
                            TextField("Name", text: $name)
                                .foregroundStyle(Theme.textPrimary)
                                .focused($focusedField, equals: .name)
                                .accessibilityLabel("Name")
                                .accessibilityIdentifier("meal.edit.name")
                        }
                        field("RESTAURANT / BRAND") {
                            TextField("Optional — who sold it", text: $sellerName)
                                .foregroundStyle(Theme.textPrimary)
                                .focused($focusedField, equals: .seller)
                                .accessibilityLabel("Restaurant or brand")
                                .accessibilityIdentifier("meal.edit.seller")
                        }
                        field("CALORIES") {
                            HStack {
                                TextField("kcal", text: $kcalText)
                                    .keyboardType(.numberPad)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                    .focused($focusedField, equals: .kcal)
                                    .onChange(of: kcalText) {
                                        // Number pad or not, text can arrive as paste/dictation —
                                        // keep the field honest instead of silently ignoring "12a"
                                        // at save time.
                                        let digits = kcalText.filter(\.isNumber)
                                        if digits != kcalText { kcalText = digits; return }
                                        if programmaticKcalWrite {
                                            programmaticKcalWrite = false
                                        } else {
                                            kcalEdited = true
                                        }
                                    }
                                    .accessibilityLabel("Calories per serving")
                                    .accessibilityIdentifier("meal.edit.kcal")
                                // Inline Done, same pattern as the confirmation sheet's kcal
                                // editor — the number pad has no return key, and a keyboard-
                                // placement toolbar renders as a stray floating capsule on
                                // iOS 27 (it sat on top of the Save bar).
                                if focusedField == .kcal {
                                    Button("Done") { focusedField = nil }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityIdentifier("meal.edit.kcalDone")
                                } else {
                                    Text("kcal")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        // The lookup cluster stays glued to the number it describes: where
                        // it came from, the honest override note, and the re-lookup door.
                        Text((rescanResult?.provenance ?? entry.provenance).detailLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("meal.edit.source")
                        if kcalChanged {
                            Text("Will be logged as your number")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)   // honesty string — legible tier
                                .accessibilityIdentifier("meal.edit.userStatedNote")
                        }

                        // Re-run the lookup ladder against the edited name/restaurant — the
                        // "I fixed the seller, now find MY salad" path. (A magnifier, not the
                        // relog arrow — "Log again today" below is a different action.)
                        Button {
                            Task { await rescan() }
                        } label: {
                            HStack(spacing: 6) {
                                if rescanning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text(rescanning ? "Looking up…" : "Look up again")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(rescanning || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("meal.edit.rescan")

                        // P6 refresh/alternates: every row here passed adjudication — never
                        // raw search noise (N6). Picking one previews it exactly like the
                        // primary re-lookup; Save records it.
                        if !alternates.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("NOT THIS? PICK ANOTHER MATCH")
                                    .font(.caption.weight(.semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.textTertiary)
                                ForEach(Array(alternates.enumerated()), id: \.offset) { index, alternate in
                                    Button {
                                        pick(alternate)
                                    } label: {
                                        HStack(alignment: .firstTextBaseline) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(alternate.name)
                                                    .font(.footnote.weight(.medium))
                                                    .foregroundStyle(Theme.textPrimary)
                                                    .multilineTextAlignment(.leading)
                                                Text(alternate.nutrition.provenance.detailLabel)
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                            Spacer()
                                            Text("\(Int(alternate.nutrition.facts.energy.midpointKcal.rounded())) kcal")
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(Theme.textPrimary)
                                        }
                                        .padding(10)
                                        .background(Theme.surface2,
                                                    in: RoundedRectangle(cornerRadius: Theme.radiusInset, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("meal.edit.alternate.\(index)")
                                }
                            }
                        }

                        // A plain settings-style row, NOT field() chrome: a stepper in a
                        // full-width input card read as a giant empty text box at ×1.
                        HStack {
                            Text("QUANTITY")
                                .font(.caption.weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                            // The kcal field is PER SERVING; say what the day row will show.
                            if quantity > 1, let each = Double(kcalText) {
                                Text("\(quantity) × \(Int(each)) = \(Int(each) * quantity) kcal")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("meal.edit.quantityTotal")
                            }
                            QuantityStepper(quantity: $quantity, showsCount: quantity <= 1)
                                .accessibilityIdentifier("meal.edit.quantity")
                        }
                        .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            // The chip rows get the same caps label rhythm as every field.
                            Text("WHEN")
                                .font(.caption.weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(Theme.textTertiary)
                            WhenRow(mealSlot: $mealSlot, date: $date)
                        }
                        .padding(.top, 4)

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.hot)
                        }

                        // The full action set lives here too — the sheet is the surface every
                        // user finds by plain tapping, so nothing is long-press-only.
                        // Guarded while dirty: it relogs the ORIGINAL entry, and someone who
                        // just typed a new number would reasonably expect their edit.
                        Button {
                            Task { await logAgainToday() }
                        } label: {
                            Label("Log again today", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isDirty ? Theme.textTertiary : Theme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDirty)
                        .padding(.top, 2)
                        .accessibilityIdentifier("meal.edit.logAgain")
                        if isDirty {
                            Text("Save your edits first — this relogs the original entry.")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }

                        // Destructive stands apart from the constructive stack (a full-width
                        // Delete one thumb-length under Save invites the worst mis-tap).
                        Divider()
                            .overlay(Theme.hairline)
                            .padding(.top, 18)
                        Button(role: .destructive) {
                            confirmingDelete = true   // one tap from permanent — confirm first
                        } label: {
                            Text("Delete entry")
                                .font(.subheadline)
                                .foregroundStyle(Theme.hot)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                        .accessibilityIdentifier("meal.edit.delete")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            // The primary action never scrolls away (keyboard up + alternates expanded used
            // to push Save off-screen) — same pinned-bar pattern as the confirmation sheet.
            // Hidden while a field is focused: riding above the keyboard it stacked on the
            // chips and collided with the inline Done — you finish typing, then you save.
            .safeAreaInset(edge: .bottom) {
                if focusedField == nil {
                    PrimaryButton(title: saving ? "Saving…" : "Save changes", systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("meal.edit.save")
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { confirmingDiscard = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .confirmationDialog("Delete \"\(entry.name)\"?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await recorder.delete(entryID: entry.id)
                            onSaved()
                            dismiss()
                        } catch {
                            // Same honesty as save(): a failed delete keeps the sheet
                            // open and says so, never a silent success.
                            self.error = "Couldn't delete the entry. Try again."
                        }
                    }
                }
            }
        }
        // Swipe-dismiss stays free while there's nothing to lose (HIG); with edits pending
        // it routes through the same discard confirm as Cancel.
        .interactiveDismissDisabled(isDirty)
    }

    private var kcalChanged: Bool {
        kcalEdited && Double(kcalText) != nil
    }

    /// Anything the user has changed but not saved — gates swipe-dismiss, Cancel, and
    /// "Log again today" (which deliberately relogs the original).
    private var isDirty: Bool {
        name != entry.name
            || trimmedSeller != (entry.seller?.name ?? "")
            || kcalChanged
            || quantity != entry.quantity
            || mealSlot != entry.meal
            || date != entry.date
            || rescanResult != nil
    }

    private var trimmedSeller: String {
        sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-run the lookup ladder with the edited name/restaurant. The result previews into
    /// the kcal field (programmatic — doesn't count as "your number") and records on Save.
    private func rescan() async {
        focusedField = nil   // tapping an action means typing is done — free the Save bar
        rescanning = true
        defer { rescanning = false }
        let item = DraftItem(name: name.trimmingCharacters(in: .whitespaces))
        let seller = trimmedSeller.isEmpty ? nil : Seller(name: trimmedSeller)
        let (resolved, others, _) = await resolver.resolveWithAlternates(
            item: item, seller: seller, capture: nil, answers: [])
        rescanResult = resolved
        alternates = others
        programmaticKcalWrite = true
        kcalText = String(Int(resolved.facts.energy.midpointKcal.rounded()))
        kcalEdited = false
    }

    /// Adopt an alternate wholesale: its name, number, and provenance become the preview
    /// (recorded on Save via the same `rescanResult` path as the primary re-lookup).
    private func pick(_ alternate: ResolvedAlternative) {
        focusedField = nil
        name = alternate.name
        rescanResult = alternate.nutrition
        programmaticKcalWrite = true
        kcalText = String(Int(alternate.nutrition.facts.energy.midpointKcal.rounded()))
        kcalEdited = false
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var edited = entry.edited(
            name: name != entry.name ? name : nil,
            kcal: kcalChanged ? Double(kcalText) : nil,
            quantity: quantity != entry.quantity ? quantity : nil,
            meal: mealSlot != entry.meal ? mealSlot : nil,
            date: date != entry.date ? date : nil
        )
        if let rescanResult {
            // The re-lookup's facts + provenance record wholesale — unless the user typed
            // over the kcal afterwards, which makes the energy theirs (macros kept).
            edited.facts = rescanResult.facts
            edited.provenance = rescanResult.provenance
            if kcalChanged, let kcal = Double(kcalText), kcal > 0 {
                edited.facts.energy = .exact(kcal: kcal)
                edited.provenance = .userStated
            }
        }
        edited.seller = trimmedSeller.isEmpty
            ? nil
            : Seller(
                name: trimmedSeller,
                // The domain hint survives only while the name it belongs to does.
                domainHint: trimmedSeller == entry.seller?.name ? entry.seller?.domainHint : nil
            )
        do {
            try await recorder.replace(entry, with: edited)
            onSaved()
            dismiss()
        } catch {
            self.error = "Couldn't save the change. Try again."
        }
    }

    /// A fresh copy of the ORIGINAL entry lands on today (unsaved edits in the fields stay
    /// unsaved — this is "same thing again", not "save + duplicate").
    private func logAgainToday() async {
        let fresh = entry.relogged()
        do {
            try await recorder.record(fresh)
            onRelogged?(fresh.id)
            dismiss()
        } catch {
            self.error = "Couldn't log it again. Try again."
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            content()
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
    }
}
