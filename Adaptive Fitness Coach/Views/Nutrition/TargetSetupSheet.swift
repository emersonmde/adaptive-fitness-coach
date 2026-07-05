import SwiftUI
import AdaptiveCore

/// Sets (or edits) the daily calorie target. With Health body data: a computed suggestion —
/// goal chips + activity picker + the live number with honest provenance ("From your Health
/// data, Mifflin-St Jeor") — confirm or override. Without: manual entry only, and the copy
/// never accuses (HealthKit hides read denial by design).
struct TargetSetupSheet: View {
    @Bindable var targetStore: CalorieTargetStore
    let bodyProfileSource: any BodyProfileSource

    @State private var profile: BodyProfile?
    @State private var profileLoaded = false
    @State private var goal: CalorieGoal = .lose
    @State private var activity: ActivityLevel = .light
    @State private var overrideText = ""
    @FocusState private var overrideFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !profileLoaded {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        } else if let profile {
                            suggestionContent(profile)
                        } else {
                            manualContent
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Daily target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if targetStore.target != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove") {
                            targetStore.clear()
                            dismiss()
                        }
                        .foregroundStyle(Theme.hot)
                    }
                }
            }
            .task {
                try? await bodyProfileSource.requestAuthorization()
                profile = try? await bodyProfileSource.currentProfile()
                if let existingGoal = targetStore.goal { goal = existingGoal }
                if let existing = targetStore.target { overrideText = String(existing) }
                profileLoaded = true
            }
        }
    }

    // MARK: - With Health data

    private var suggested: Int? {
        profile.map { CalorieTargetCalculator.suggestedTarget(profile: $0, activity: activity, goal: goal) }
    }

    private func suggestionContent(_ profile: BodyProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's the goal?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(CalorieGoal.allCases, id: \.self) { candidate in
                    chip(candidate.displayName, selected: goal == candidate,
                         id: "meal.target.goal.\(candidate.rawValue)") {
                        goal = candidate
                        // A typed override survives chip taps (it used to be silently
                        // erased); its precedence is stated under the suggestion instead.
                    }
                }
            }

            Text("How active are your days, outside workouts?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 6) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Button {
                        activity = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                // Bare labels ("Light") have no anchor — one concrete line
                                // is what lets a novice self-classify honestly.
                                Text(Self.anchor(for: level))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: activity == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(activity == level ? Theme.accent : Theme.textTertiary)
                        }
                        .padding(12)
                        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radiusInset))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal.target.activity.\(level.rawValue)")
                }
            }

            if let suggested {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(suggested.formatted()) kcal / day")
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("meal.target.suggested")
                    }
                    Text("From your Health data (Mifflin-St Jeor)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if Int(overrideText.trimmingCharacters(in: .whitespaces)) != nil {
                        Text("Your number below overrides this suggestion")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 4)

                overrideField

                PrimaryButton(title: "Use \(effectiveTarget?.formatted() ?? "")", systemImage: "checkmark") {
                    save()
                }
                .disabled(effectiveTarget == nil)
                .accessibilityIdentifier("meal.target.confirm")
            }
        }
    }

    // MARK: - Without Health data

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Health doesn't have the body data for a suggestion — set the number directly.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            overrideField
            PrimaryButton(title: "Set target", systemImage: "checkmark") { save() }
                .disabled(effectiveTarget == nil)
                .accessibilityIdentifier("meal.target.confirm")
        }
    }

    private var overrideField: some View {
        HStack {
            TextField("Or your own number", text: $overrideText)
                .keyboardType(.numberPad)
                .focused($overrideFocused)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("meal.target.field")
            Text("kcal")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
            if !overrideText.isEmpty {
                Button {
                    overrideText = ""   // explicit clear — never silent
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("Clear your number")
            }
        }
        .padding(12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        // numberPad has no return key — without this the keyboard is a trap (same fix
        // the entry edit sheet carries).
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { overrideFocused = false }
            }
        }
    }

    /// One concrete anchor per level — self-classification needs an example, not a synonym.
    private static func anchor(for level: ActivityLevel) -> String {
        switch level {
        case .sedentary: "Mostly seated — desk work, little walking"
        case .light: "On your feet some of the day, some walking"
        case .moderate: "Regularly walking or physically busy"
        case .active: "On your feet most of the day, physical work"
        }
    }

    /// Manual number when typed (sanity-clamped), else the suggestion.
    private var effectiveTarget: Int? {
        if let typed = Int(overrideText.trimmingCharacters(in: .whitespaces)), typed > 0 {
            return min(max(typed, 800), 6_000)
        }
        return suggested
    }

    private func save() {
        guard let target = effectiveTarget else { return }
        targetStore.set(target: target, goal: profile != nil ? goal : nil)
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
