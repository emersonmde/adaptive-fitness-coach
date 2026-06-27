import SwiftUI
import AdaptiveCore

/// P2 — create a routine: name it, pick repeat days, choose a type. In P0 only Adaptive Run
/// is functional; the type picker still shows Strength (disabled) so the model is visible.
struct NewRoutineView: View {
    let store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var type: RoutineType = .adaptiveRun

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedDays.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Morning Run", text: $name)
                }

                Section("Repeat days") {
                    DayPicker(selection: $selectedDays)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(RoutineType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !type.isAvailable {
                        Text("Strength routines arrive in a later update. Pick Adaptive Run for now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Adaptive runs build themselves from your heart rate — no exercises to add.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { save() }
                        .disabled(!canSave || !type.isAvailable)
                }
            }
        }
    }

    private func save() {
        let routine = Routine(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            repeatDays: selectedDays
        )
        store.add(routine)
        dismiss()
    }
}
