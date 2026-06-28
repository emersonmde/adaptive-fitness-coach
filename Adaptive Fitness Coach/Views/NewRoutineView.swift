import SwiftUI
import AdaptiveCore

/// P2 — create a routine: name it, pick repeat days, choose a type. In P0 only Adaptive Run
/// is functional; the type picker still shows Strength (disabled) so the model is visible.
///
/// The design's type-branch (Strength → workout library, Adaptive Run → straight to scheduling)
/// is deferred: with only Adaptive Run selectable, "Next" saves and returns to the week list,
/// where the routine is opened to schedule it. The library branch lands with P1.
struct NewRoutineView: View {
    let store: RoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var type: RoutineType = .adaptiveRun
    @State private var durationMinutes = 30

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedDays.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        FieldSection(title: "NAME") {
                            TextField("e.g. Morning Run", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(Theme.textPrimary)
                        }

                        FieldSection(title: "REPEAT DAYS") {
                            DayPicker(selection: $selectedDays)
                        }

                        FieldSection(title: "DURATION") {
                            DurationStepper(minutes: $durationMinutes)
                        }

                        FieldSection(title: "TYPE") {
                            VStack(alignment: .leading, spacing: 12) {
                                TypeSelector(selection: $type)
                                Text(type.isAvailable
                                     ? "Adaptive runs build themselves from your heart rate — no exercises to add."
                                     : "Strength routines arrive in a later update. Pick Adaptive Run for now.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
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
        store.add(Routine(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            repeatDays: selectedDays,
            durationMinutes: durationMinutes
        ))
        dismiss()
    }
}

/// Two-option type selector that shows each type's semantic dot — teaching the watch's color
/// language (green run / blue strength) before the user ever runs. Strength is disabled in P0.
struct TypeSelector: View {
    @Binding var selection: RoutineType

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RoutineType.allCases, id: \.self) { type in
                let isOn = selection == type
                Button {
                    if type.isAvailable { selection = type }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(RoutineTheme.tint(for: type)).frame(width: 8, height: 8)
                        Text(type.displayName)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(isOn ? Theme.surface2 : .clear,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isOn ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1)
                    )
                    .foregroundStyle(type.isAvailable ? Theme.textPrimary : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!type.isAvailable)
            }
        }
    }
}
