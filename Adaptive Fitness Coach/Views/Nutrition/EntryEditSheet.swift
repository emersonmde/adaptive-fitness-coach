import SwiftUI
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
    @Environment(\.dismiss) private var dismiss

    init(entry: MealEntry, recorder: any NutritionRecorder, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.recorder = recorder
        self.onSaved = onSaved
        _name = State(initialValue: entry.name)
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
                        field("CALORIES") {
                            HStack {
                                TextField("kcal", text: $kcalText)
                                    .keyboardType(.numberPad)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                    .onChange(of: kcalText) { kcalEdited = true }
                                    .accessibilityIdentifier("meal.edit.kcal")
                                Text("kcal")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        if kcalChanged {
                            Text("Will be logged as your number")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                                .accessibilityIdentifier("meal.edit.userStatedNote")
                        }

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
                            Task {
                                do {
                                    try await recorder.delete(entryID: entry.id)
                                    onSaved()
                                    dismiss()
                                } catch {
                                    // Same honesty as save(): a failed delete keeps the
                                    // sheet open and says so, never a silent success.
                                    self.error = "Couldn't delete the entry — try again."
                                }
                            }
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
            }
        }
        .preferredColorScheme(.dark)
    }

    private var kcalChanged: Bool {
        kcalEdited && Double(kcalText) != nil
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let newKcal = kcalChanged ? Double(kcalText) : nil
        let edited = entry.edited(
            name: name != entry.name ? name : nil,
            kcal: newKcal,
            meal: mealSlot != entry.meal ? mealSlot : nil,
            date: date != entry.date ? date : nil
        )
        do {
            try await recorder.replace(entry, with: edited)
            onSaved()
            dismiss()
        } catch {
            self.error = "Couldn't save the change — try again."
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
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
