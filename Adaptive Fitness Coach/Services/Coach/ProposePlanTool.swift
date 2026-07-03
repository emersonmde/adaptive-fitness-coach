import Foundation
import FoundationModels
import AdaptiveCore

/// The tool the model calls when it judges the intake complete — the natural "here's what I'd
/// suggest" moment. Arguments are the guided `GenerablePlan`; the call validates through the
/// pinned exchange path and hands the surviving proposal to the session (which emits it as a
/// `CoachEvent.proposal` for the UI to render as cards).
///
/// Validation failures return a corrective message to the *model* (so it can fix the plan and
/// call again) instead of failing the turn — the user never sees a raw schema error.
struct ProposePlanTool: Tool {
    let name = "propose_plan"
    let description = """
    Present the drafted workout plan to the user as reviewable routine cards. Call this once \
    you have enough from the intake to propose, and again with a revised plan after feedback. \
    Never write the plan as text or JSON in the conversation — this tool is the only way to \
    show it.
    """

    /// Receives each validated proposal (the session wires this to its event stream).
    let onProposal: @Sendable (CoachProposal) -> Void

    func call(arguments: GenerablePlan) async throws -> String {
        let proposal: CoachProposal
        do {
            proposal = try CoachProposalValidator.validate(
                rawJSON: try arguments.exchangeJSON(),
                summary: arguments.summary
            )
        } catch {
            return """
            The plan could not be validated (\(error)). Check that every exercise id comes \
            from the vocabulary in your instructions and every routine has at least one card, \
            then call propose_plan again.
            """
        }
        onProposal(proposal)
        var note = "The plan is now on screen as routine cards the user can review and apply."
        if proposal.droppedCardCount > 0 {
            note += " \(proposal.droppedCardCount) card(s) were dropped as invalid; the user was told."
        }
        note += " Briefly say why the plan fits and invite feedback — do not repeat the plan's contents."
        return note
    }
}
