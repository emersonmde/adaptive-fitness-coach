import SwiftUI
import AdaptiveCore

/// Sets (or edits) the daily calorie goal.
///
/// With Health body data: a **deficit** (kcal/day below maintenance) — quick presets plus a custom
/// field. The budget isn't a single fixed number: it's `BMR − deficit` at rest, rising through the
/// day as the watch banks active energy, and tuned to the user's own weight trend over time. The
/// sheet explains that so the live gauge isn't a surprise.
///
/// Without Health body data: a plain fixed number (the old behavior); the copy never accuses
/// (HealthKit hides read denial by design).
struct TargetSetupSheet: View {
    @Bindable var targetStore: CalorieTargetStore
    let bodyProfileSource: any BodyProfileSource

    @State private var profile: BodyProfile?
    @State private var profileLoaded = false
    @State private var deficit = 500
    @State private var deficitText = ""
    @State private var overrideText = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Quick-pick deficits (kcal/day). 0 = maintain.
    private static let presets = [0, 250, 500, 750, 1000]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !profileLoaded {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        } else if let profile {
                            deficitContent(profile)
                        } else {
                            manualContent
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Daily goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if targetStore.hasTarget {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove") {
                            targetStore.clear()
                            dismiss()
                        }
                        .foregroundStyle(Theme.hot)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            .task {
                try? await bodyProfileSource.requestAuthorization()
                profile = try? await bodyProfileSource.currentProfile()
                if let existing = targetStore.deficitKcal { deficit = existing }
                if let existingFixed = targetStore.fixedTargetKcal { overrideText = String(existingFixed) }
                profileLoaded = true
            }
        }
    }

    // MARK: - With Health data (deficit)

    private var bmr: Double? { profile.map(CalorieTargetCalculator.bmr) }

    /// The resting budget (before any active energy is earned) — the number the user sees first
    /// thing in the morning, floored for safety.
    private var restingTarget: Int? {
        guard let bmr else { return nil }
        return DynamicDayBudget(bmrKcal: bmr, deficitKcal: Double(deficit),
                                activeEarnedKcal: 0, consumedKcal: 0,
                                basalTrust: targetStore.basalTrust).targetKcal
    }

    private func deficitContent(_ profile: BodyProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How big a daily deficit?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            // Preset chips.
            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { value in
                    chip(label(for: value), selected: deficit == value && deficitText.isEmpty,
                         id: "meal.target.deficit.\(value)") {
                        deficit = value
                        deficitText = ""
                        fieldFocused = false
                    }
                }
            }

            // Custom deficit.
            fieldRow(text: $deficitText, placeholder: "Custom deficit", unit: "kcal below",
                     id: "meal.target.deficitField")
                .onChange(of: deficitText) { _, new in
                    if let typed = Int(new.trimmingCharacters(in: .whitespaces)) {
                        deficit = min(max(typed, 0), 1500)   // cap: the floor still guards intake
                    }
                }

            if let restingTarget {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(restingTarget.formatted()) kcal to start the day")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("meal.target.resting")
                    Text("Rises as your watch logs activity — eat back what you burn, or bank it toward your deficit.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cal = targetStore.calibration, cal.isConfident, let dev = cal.deviationPercent, dev != 0 {
                        Text("Tuned to your weigh-ins — runs \(abs(dev))% \(dev < 0 ? "below" : "above") the textbook estimate.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)

                PrimaryButton(title: "Use this goal", systemImage: "checkmark") { saveDeficit() }
                    .accessibilityIdentifier("meal.target.confirm")
            }
        }
    }

    private func label(for deficit: Int) -> String {
        deficit == 0 ? "Maintain" : "−\(deficit)"
    }

    // MARK: - Without Health data (fixed number)

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Health doesn't have the body data for a deficit budget — set the number directly.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            fieldRow(text: $overrideText, placeholder: "Daily calories", unit: "kcal",
                     id: "meal.target.field")
            PrimaryButton(title: "Set target", systemImage: "checkmark") { saveFixed() }
                .disabled(fixedTarget == nil)
                .accessibilityIdentifier("meal.target.confirm")
        }
    }

    private var fixedTarget: Int? {
        guard let typed = Int(overrideText.trimmingCharacters(in: .whitespaces)), typed > 0 else { return nil }
        return min(max(typed, 800), 6_000)
    }

    // MARK: - Shared

    private func fieldRow(text: Binding<String>, placeholder: String, unit: String, id: String) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .focused($fieldFocused)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusInset))
    }

    private func saveDeficit() {
        guard let bmr else { return }
        // Map to the nearest legacy goal so the export pack / any consumer still reads sensibly.
        let mappedGoal: CalorieGoal = deficit > 100 ? .lose : (deficit < -100 ? .gain : .maintain)
        targetStore.setDeficit(deficit, goal: mappedGoal, bmrKcal: bmr)
        Task { await targetStore.refreshCalibration(force: true) }
        dismiss()
    }

    private func saveFixed() {
        guard let target = fixedTarget else { return }
        targetStore.setFixed(target)
        dismiss()
    }

    private func chip(_ label: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.bg : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? Theme.accent : Theme.surface2))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.hairline))
        }
        .accessibilityIdentifier(id)
    }
}
