import SwiftUI
import AdaptiveCore

/// Create a routine: name it and pick repeat days, then build it from cards. There's no upfront
/// type choice anymore — a routine is whatever cards you add (a run, strength moves, rests), so
/// "Next" goes straight to the card builder, which creates the routine when saved.
struct NewRoutineView: View {
    let store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var showingBuilder = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    /// Only the name gates Next. Repeat days are optional: an unscheduled routine is a real
    /// thing (started ad hoc from the watch, shown without day badges on the week screen),
    /// and days stay editable later in the routine's detail — requiring them here forced a
    /// fake commitment before the routine even existed.
    private var canContinue: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        FieldSection(title: "NAME") {
                            TextField("e.g. Push Day", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        FieldSection(title: "REPEAT DAYS") {
                            VStack(alignment: .leading, spacing: 10) {
                                DayPicker(selection: $selectedDays)
                                Text("Optional — leave empty for an unscheduled routine you start any time. You can add days later.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Text("Next, build the routine from cards — a run, strength moves, and rests, in any order.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingBuilder) {
                RoutineBuilderView { cards, rounds in
                    store.add(Routine(name: trimmedName, repeatDays: selectedDays, cards: cards, rounds: rounds))
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { showingBuilder = true }
                        .disabled(!canContinue)
                }
            }
        }
    }
}
