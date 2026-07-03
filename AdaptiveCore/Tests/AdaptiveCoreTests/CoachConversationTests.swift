import Foundation
import Testing
@testable import AdaptiveCore

/// Drives the conversation state machine with the scripted engine — the same deterministic
/// path `-simulateCoach` uses in the simulator.
@MainActor
struct CoachConversationTests {

    private struct ScriptError: Error {}

    private func makeConversation(turns: [ScriptedCoachEngine.Turn]) throws -> CoachConversation {
        try CoachConversation(
            engine: ScriptedCoachEngine(turns: turns),
            intent: .buildNewPlan,
            context: .empty
        )
    }

    /// Poll until the in-flight turn settles (events hop through an async stream; there is no
    /// clock involved, so this converges immediately in practice).
    private func settle(_ conversation: CoachConversation) async {
        while conversation.isResponding {
            await Task.yield()
        }
    }

    @Test func transcriptOrdersUserThenCoach() async throws {
        let conversation = try makeConversation(turns: [
            .init(text: "What equipment do you have?"),
        ])
        conversation.send("Build me a plan")
        await settle(conversation)

        #expect(conversation.transcript.count == 2)
        guard case let .user(userText) = conversation.transcript[0].kind,
              case let .coach(coachText) = conversation.transcript[1].kind else {
            Issue.record("unexpected transcript shape")
            return
        }
        #expect(userText == "Build me a plan")
        #expect(coachText == "What equipment do you have?")
        #expect(conversation.streamingText.isEmpty)   // folded on finish
        #expect(!conversation.isResponding)
    }

    @Test func proposalLandsInTranscriptAndLatest() async throws {
        let plan = CoachProposal(
            routines: [Routine(name: "Coached", cards: [.run(RunCard())])],
            summary: "One easy run."
        )
        let conversation = try makeConversation(turns: [
            .init(text: "Here's what I'd start with.", proposal: plan),
        ])
        conversation.send("Go ahead")
        await settle(conversation)

        #expect(conversation.latestProposal == plan)
        // Prose folds before the proposal entry, in spoken order.
        let kinds = conversation.transcript.map(\.kind)
        guard kinds.count == 3,
              case .user = kinds[0], case .coach = kinds[1], case .proposal = kinds[2] else {
            Issue.record("expected user → coach → proposal, got \(kinds.count) entries")
            return
        }
    }

    @Test func failedTurnIsRetryable() async throws {
        let conversation = try makeConversation(turns: [
            .init(text: "", error: ScriptError()),
            .init(text: "Back with you — what's the goal?"),
        ])
        conversation.send("Hello")
        await settle(conversation)

        let failure = try #require(conversation.transcript.last)
        guard case .failure(_, let retryText) = failure.kind else {
            Issue.record("expected a failure entry")
            return
        }
        #expect(retryText == "Hello")

        conversation.retry(failure)
        await settle(conversation)

        // The failure entry is replaced by the successful second turn.
        #expect(!conversation.transcript.contains { if case .failure = $0.kind { true } else { false } })
        guard case let .coach(text) = conversation.transcript.last?.kind else {
            Issue.record("expected a coach reply after retry")
            return
        }
        #expect(text.contains("goal"))
    }

    @Test func emptyAndWhitespaceSendsAreIgnored() async throws {
        let conversation = try makeConversation(turns: [.init(text: "Hi!")])
        conversation.send("   \n")
        #expect(conversation.transcript.isEmpty)
        #expect(!conversation.isResponding)
    }

    @Test func sendWhileRespondingIsIgnored() async throws {
        let conversation = try makeConversation(turns: [.init(text: "First reply")])
        conversation.send("one")
        conversation.send("two")   // dropped: a turn is in flight
        await settle(conversation)
        let userMessages = conversation.transcript.filter {
            if case .user = $0.kind { true } else { false }
        }
        #expect(userMessages.count == 1)
    }

    @Test func scriptRepeatsLastTurnPastTheEnd() async throws {
        let conversation = try makeConversation(turns: [.init(text: "Only turn")])
        conversation.send("a")
        await settle(conversation)
        conversation.send("b")
        await settle(conversation)
        let coachReplies = conversation.transcript.compactMap {
            if case let .coach(text) = $0.kind { text } else { nil }
        }
        #expect(coachReplies == ["Only turn", "Only turn"])
    }

    @Test func unavailableEngineRefusesSession() {
        let engine = ScriptedCoachEngine(turns: [], availability: .unavailable(reason: "testing"))
        #expect(throws: (any Error).self) {
            _ = try engine.makeSession(intent: .buildNewPlan, context: .empty)
        }
    }

    @Test func demoIntakeProposalImportsCleanly() throws {
        // The canned demo's proposal must be real library movements so an applied demo plan
        // behaves exactly like a hand-built routine.
        let engine = ScriptedCoachEngine.demoIntake()
        _ = engine   // construction alone validates the force-unwrapped library ids
    }
}
