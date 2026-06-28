import SwiftUI
import AdaptiveCore

/// P2 — create a routine: name it, pick repeat days, choose a type. The type branches the flow
/// (the design's type-branch): **Adaptive Run** → "Next" saves and returns to the week to be
/// scheduled; **Strength** → "Next" pushes the arrange-as-cards builder, where the exercise
/// sequence is assembled before the routine is created.
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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

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

                        if type == .adaptiveRun {
                            FieldSection(title: "DURATION") {
                                DurationStepper(minutes: $durationMinutes)
                            }
                        }

                        FieldSection(title: "TYPE") {
                            VStack(alignment: .leading, spacing: 12) {
                                TypeSelector(selection: $type)
                                Text(type == .adaptiveRun
                                     ? "Adaptive runs build themselves from your heart rate — no exercises to add."
                                     : "Next, you'll pick exercises and arrange them into a sequence.")
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
            .navigationDestination(isPresented: $showingBuilder) {
                RoutineBuilderView { items in
                    store.add(Routine(
                        name: trimmedName,
                        type: .strength,
                        repeatDays: selectedDays,
                        exercises: items
                    ))
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { next() }
                        .disabled(!canSave)
                }
            }
        }
    }

    @State private var showingBuilder = false

    /// Adaptive run saves immediately; strength advances to the exercise builder, which creates
    /// the routine once its sequence is assembled.
    private func next() {
        switch type {
        case .adaptiveRun:
            store.add(Routine(
                name: trimmedName,
                type: .adaptiveRun,
                repeatDays: selectedDays,
                durationMinutes: durationMinutes
            ))
            dismiss()
        case .strength:
            showingBuilder = true
        }
    }
}

/// Two-option type selector that shows each type's semantic dot — teaching the watch's color
/// language (green run / blue strength) before the user ever runs. Both types are selectable in P1.
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
