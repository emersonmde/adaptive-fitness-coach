import SwiftUI
import AdaptiveCore

/// A wrapper so a parsed-but-not-yet-applied import can drive a `.sheet(item:)`.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let routines: [Routine]
}

/// Confirms a routine import (a coach proposal, or the JSON Claude returned parsed by
/// `RoutineExchange`) before it touches the store. This is the app's load-bearing review gate —
/// EVERY AI-authored plan funnels through here — so it renders each routine with the same
/// identity treatment as the proposal card in the chat (type icon, colored NEW/UPDATES badge),
/// plus what only this screen can answer: exactly which cards land, on which days, and what an
/// update does to the routine you already have (replaces its cards; earned run/weight
/// progression is grafted across by `RoutineStore.importRoutines` — say so, honestly).
struct ImportRoutinesSheet: View {
    let candidate: ImportCandidate
    let existingNames: Set<String>
    /// Card count of each existing routine by name, for the update diff line ("replaces the
    /// N cards you have now"). Optional: the manual clipboard path may not supply it, in which
    /// case updates get the same line without a count. Matched exactly by name, like
    /// `existingNames` (the store's merge is more forgiving — folded — but the badge and the
    /// diff line should agree with each other).
    var existingCardCounts: [String: Int] = [:]
    /// Apply the import; returns (updated, added) for the confirmation.
    let onApply: ([Routine]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Review before it's applied. Matching names update your existing routines; the rest are added.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(candidate.routines) { routine in
                            routineCard(routine)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Import \(candidate.routines.count) Routine\(candidate.routines.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            // The commit action is the screen's one focal CTA, pinned like the app's other
            // commit sheets — not a bare toolbar word.
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Apply", systemImage: "checkmark") {
                    onApply(candidate.routines)
                    dismiss()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.bg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Routine cards

    /// One incoming routine, styled to match the chat's proposal card: type icon + name +
    /// colored badge up top, then days, the full card list, and (for updates) the diff line.
    private func routineCard(_ routine: Routine) -> some View {
        let isUpdate = existingNames.contains(routine.name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: routine.type == .strength ? "dumbbell.fill" : "figure.run")
                    .font(.caption)
                    .foregroundStyle(routine.type == .strength ? Theme.strength : Theme.run)
                    .frame(width: 20)
                Text(routine.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Text(isUpdate ? "UPDATES" : "NEW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isUpdate ? Theme.info : Theme.accent)
            }

            Text(scheduleLine(routine))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(routine.cards.enumerated()), id: \.offset) { _, card in
                    Text("• \(cardSummary(card))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if routine.rounds > 1 {
                    Text("Repeats \(routine.rounds)×")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if isUpdate {
                // What "UPDATES" costs and what it doesn't: the incoming cards replace the
                // existing stack, but earned progression is grafted across by the store
                // (`graftingRunProgression`) — the user's run/weight progress survives.
                Text("\(replacesLine(routine)) — your progressed run/weights carry over.")
                    .font(.footnote)
                    .foregroundStyle(Theme.info)
            }
        }
        .padding(14)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.hairline))
    }

    /// "Mon Wed Fri · ~40 min", or an honest "No repeat days set" when unscheduled.
    private func scheduleLine(_ routine: Routine) -> String {
        var parts: [String] = []
        if routine.repeatDays.isEmpty {
            parts.append("No repeat days set")
        } else {
            parts.append(routine.repeatDays.sorted().map(\.shortName).joined(separator: " "))
        }
        parts.append("~\(routine.estimatedMinutes) min")
        return parts.joined(separator: " · ")
    }

    /// Count-level diff for an update, when the presenter told us the existing card count.
    private func replacesLine(_ routine: Routine) -> String {
        if let count = existingCardCounts[routine.name] {
            return "Replaces the \(count) card\(count == 1 ? "" : "s") you have now"
        }
        return "Replaces its current cards"
    }

    private func cardSummary(_ card: WorkoutCard) -> String {
        switch card {
        case let .run(c):
            return "Run \(c.durationMinutes) min (+\(c.warmupMinutes)+\(c.cooldownMinutes) walk)"
        case let .exercise(item):
            let name = ExerciseLibrary.exercise(id: item.exerciseId)?.name ?? item.exerciseId
            if let hold = item.holdSeconds { return "\(name) — \(Int(hold))s hold" }
            let load = item.seedWeight.map { " · \($0.displayString())" } ?? " · bodyweight"
            return "\(name) — \(item.reps ?? 0) reps\(load)"
        case let .rest(c):
            return "Rest \(Int(c.seconds))s"
        }
    }
}
