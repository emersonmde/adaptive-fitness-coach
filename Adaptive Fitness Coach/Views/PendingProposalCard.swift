import SwiftUI
import AdaptiveCore

/// The P6 structural-confirm card: a load step-up or run-shape graduation the watch proposed,
/// waiting for the user's word. One dominant line (the change), the policy's reason as the
/// quiet second line, Confirm/Hold as the only actions. Declining is holding — the routine
/// simply keeps its earned seed, so there is no urgency styling and no expiry (Q5: never nag).
struct PendingProposalCard: View {
    let proposal: PendingStructuralProposal
    let store: RoutineStore
    let journal: ProgressionJournal
    let proposals: ProgressionProposalStore
    /// P14 receipt: called with the one-line settled text (confirm / hold) AFTER the store
    /// mutation, so the host can collapse this card in place instead of vanishing it.
    var onSettled: ((_ text: String, _ confirmed: Bool) -> Void)? = nil

    var body: some View {
        let display = ProgressionIntake.display(for: proposal, store: store)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("STEP UP?")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(display.subject) \(display.changeText)")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(reasonLine(display.reason))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Theme.Haptics.success()
                        // Settled text is read BEFORE the store mutates — after apply the
                        // routine already holds the new value and "from → to" is gone.
                        let settled = "Stepped up — \(display.subject) \(display.changeText)"
                        withAnimation(Theme.Motion.settle) {
                            ProgressionIntake.confirm(proposal.id, store: store,
                                                      journal: journal, proposals: proposals)
                            onSettled?(settled, true)
                        }
                    } label: {
                        Text("Confirm")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.16),
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("proposal.confirm")

                    Button {
                        Theme.Haptics.selection()
                        let settled = "Kept \(currentValueText ?? "your current level") — the watch will re-propose when earned."
                        withAnimation(Theme.Motion.settle) {
                            ProgressionIntake.decline(proposal.id, store: store,
                                                      journal: journal, proposals: proposals)
                            onSettled?(settled, false)
                        }
                    } label: {
                        Text("Hold")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.surface2, in: Capsule())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("proposal.hold")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proposal.card")
    }

    /// What holding KEEPS, read from the routine's current seed ("25 lb", "12 reps",
    /// "45s hold", or the run intervals). nil when the routine has since been deleted.
    private var currentValueText: String? {
        guard let routine = store.routines.first(where: { $0.id == proposal.routineId }) else {
            return nil
        }
        if let update = proposal.update,
           let old = routine.cards.compactMap(\.exercise)
               .first(where: { $0.exerciseId == update.exerciseId }) {
            if let weight = old.seedWeight { return weight.displayString() }
            if let hold = old.holdSeconds { return "\(Int(hold))s hold" }
            if let reps = old.reps { return "\(reps) reps" }
        }
        if proposal.runUpdate != nil { return "the current intervals" }
        return nil
    }

    private func reasonLine(_ reason: String?) -> String {
        var parts: [String] = []
        if let reason { parts.append(reason.prefix(1).capitalized + reason.dropFirst()) }
        if let effort = proposal.perceivedEffort { parts.append("effort \(effort)") }
        return parts.isEmpty ? "Earned last session" : parts.joined(separator: " · ")
    }
}
