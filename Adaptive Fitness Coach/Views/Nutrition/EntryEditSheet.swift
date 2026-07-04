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

    @State private var name: String
    @State private var kcalText: String
    @State private var mealSlot: MealSlot
    @State private var date: Date
    @State private var error: String?
    @State private var saving = false
    /// The number becomes "yours" only if you actually touched the field — inferring from
    /// value comparison converted a range estimate to `.userStated` on ANY edit (slot/day),
    /// silently destroying the honest range and its assumptions.
    @State private var kcalEdited = false
    @State private var sellerName: String
    /// "Look up again": the ladder re-run against the edited name/seller. Non-nil means the
    /// save records these facts + provenance (unless the user re-types the kcal afterwards).
    @State private var rescanResult: ResolvedNutrition?
    @State private var rescanning = false
    /// Distinguishes the rescan writing the kcal preview from the user typing (only the
    /// latter makes the number "yours").
    @State private var programmaticKcalWrite = false
    @State private var confirmingDelete = false
    /// The lookup ladder, same wiring as the log flow (scripted in the simulator).
    private let resolver = MealPipelineProvider.makeResolver()
    @Environment(\.dismiss) private var dismiss

    init(entry: MealEntry, recorder: any NutritionRecorder, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.recorder = recorder
        self.onSaved = onSaved
        _name = State(initialValue: entry.name)
        _sellerName = State(initialValue: entry.seller?.name ?? "")
        _kcalText = State(initialValue: String(Int(entry.facts.energy.midpointKcal.rounded())))
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
                                .accessibilityIdentifier("meal.edit.name")
                        }
                        field("RESTAURANT / BRAND") {
                            TextField("Optional — who sold it", text: $sellerName)
                                .foregroundStyle(Theme.textPrimary)
                                .accessibilityIdentifier("meal.edit.seller")
                        }
                        field("CALORIES") {
                            HStack {
                                TextField("kcal", text: $kcalText)
                                    .keyboardType(.numberPad)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                    .onChange(of: kcalText) {
                                        if programmaticKcalWrite {
                                            programmaticKcalWrite = false
                                        } else {
                                            kcalEdited = true
                                        }
                                    }
                                    .accessibilityIdentifier("meal.edit.kcal")
                                Text("kcal")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        // Where the current number comes from — and the honest state after
                        // a re-lookup ("estimate", "verified · saladworks.com", …).
                        Text((rescanResult?.provenance ?? entry.provenance).detailLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("meal.edit.source")
                        if kcalChanged {
                            Text("Will be logged as your number")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                                .accessibilityIdentifier("meal.edit.userStatedNote")
                        }

                        // Re-run the lookup ladder against the edited name/restaurant — the
                        // "I fixed the seller, now find MY salad" path.
                        Button {
                            Task { await rescan() }
                        } label: {
                            HStack(spacing: 6) {
                                if rescanning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                Text(rescanning ? "Looking up…" : "Look up again")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(rescanning || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("meal.edit.rescan")

                        WhenRow(mealSlot: $mealSlot, date: $date)

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.hot)
                        }

                        PrimaryButton(title: saving ? "Saving…" : "Save changes", systemImage: "checkmark") {
                            Task { await save() }
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("meal.edit.save")

                        Button(role: .destructive) {
                            confirmingDelete = true   // one tap from permanent — confirm first
                        } label: {
                            Text("Delete entry")
                                .font(.subheadline)
                                .foregroundStyle(Theme.hot)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityIdentifier("meal.edit.delete")
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // The number pad has no return key — without this the keyboard is a trap.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
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
                            self.error = "Couldn't delete the entry — try again."
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var kcalChanged: Bool {
        kcalEdited && Double(kcalText) != nil
    }

    private var trimmedSeller: String {
        sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Re-run the lookup ladder with the edited name/restaurant. The result previews into
    /// the kcal field (programmatic — doesn't count as "your number") and records on Save.
    private func rescan() async {
        rescanning = true
        defer { rescanning = false }
        let item = DraftItem(name: name.trimmingCharacters(in: .whitespaces))
        let seller = trimmedSeller.isEmpty ? nil : Seller(name: trimmedSeller)
        let (resolved, _) = await resolver.resolve(item: item, seller: seller, capture: nil, answers: [])
        rescanResult = resolved
        programmaticKcalWrite = true
        kcalText = String(Int(resolved.facts.energy.midpointKcal.rounded()))
        kcalEdited = false
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var edited = entry.edited(
            name: name != entry.name ? name : nil,
            kcal: kcalChanged ? Double(kcalText) : nil,
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
            self.error = "Couldn't save the change — try again."
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
            content()
                .padding(12)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
