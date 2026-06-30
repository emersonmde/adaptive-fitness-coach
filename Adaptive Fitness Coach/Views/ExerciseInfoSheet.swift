import SwiftUI
import AdaptiveCore

/// What a movement is and how to do it — the iOS exercise help sheet, opened from the library and
/// the routine builder via an info button. Shows the form demo (the future home of an animation /
/// diagram), the muscles it works, what it's good for, how to perform it, and coaching tips. It
/// mirrors the same catalog copy the watch shows on its Exercise page. Read-only.
struct ExerciseInfoSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        demo
                        if !exercise.muscleTags.isEmpty { muscleChips }

                        FieldSection(title: "HOW TO") {
                            Text(exercise.howTo)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        FieldSection(title: "GOOD FOR") {
                            Text(exercise.goodFor)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !exercise.tips.isEmpty {
                            FieldSection(title: "TIPS") {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(exercise.tips, id: \.self) { tip in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(Theme.strength)
                                                .padding(.top, 2)
                                            Text(tip)
                                                .font(.subheadline)
                                                .foregroundStyle(Theme.textPrimary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        Text(prescription)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The form demo — an SF Symbol placeholder on a strength-tinted card. Reserved for a real
    /// animation/diagram asset later (`FormDemo.diagram`/`.animation`).
    private var demo: some View {
        let symbol: String = { if case let .symbol(name) = exercise.formDemo { return name }; return "dumbbell.fill" }()
        return Image(systemName: symbol)
            .font(.system(size: 64))
            .foregroundStyle(Theme.strength)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Theme.strength.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.strength.opacity(0.25), lineWidth: 1)
            )
    }

    private var muscleChips: some View {
        HStack(spacing: 8) {
            ForEach(exercise.muscleTags.map(\.capitalized), id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.strength)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.strength.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var prescription: String {
        switch exercise.kind {
        case let .reps(reps, weight):
            let load = weight?.displayString() ?? "bodyweight"
            return "Default: \(exercise.defaultSets) × \(reps) · \(load)"
        case let .hold(seconds):
            return "Default: \(exercise.defaultSets) × \(seconds.holdLabel) hold"
        }
    }
}
