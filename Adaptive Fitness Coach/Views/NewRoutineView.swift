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
    private var canContinue: Bool { !trimmedName.isEmpty && !selectedDays.isEmpty }

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
                            DayPicker(selection: $selectedDays)
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
