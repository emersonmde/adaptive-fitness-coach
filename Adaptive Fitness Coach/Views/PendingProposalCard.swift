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
                        withAnimation(Theme.Motion.settle) {
                            ProgressionIntake.confirm(proposal.id, store: store,
                                                      journal: journal, proposals: proposals)
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
                        withAnimation(Theme.Motion.settle) {
                            ProgressionIntake.decline(proposal.id, store: store,
                                                      journal: journal, proposals: proposals)
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

    private func reasonLine(_ reason: String?) -> String {
        var parts: [String] = []
        if let reason { parts.append(reason.prefix(1).capitalized + reason.dropFirst()) }
        if let effort = proposal.perceivedEffort { parts.append("effort \(effort)") }
        return parts.isEmpty ? "Earned last session" : parts.joined(separator: " · ")
    }
}
