import Foundation
import Observation

/// The observable state machine behind the coach sheet: folds a `CoachSession`'s event stream
/// into a transcript the UI renders. Engine-agnostic and clock-free, so the whole conversation
/// flow is unit-testable with `ScriptedCoachEngine` (the `WorkoutSessionManager` testing
/// pattern applied to chat).
///
/// One instance per sheet presentation; conversations are ephemeral (the durable artifact is
/// the routine set the user applies).
@MainActor
@Observable
public final class CoachConversation {

    /// One rendered row of the conversation.
    public struct Entry: Identifiable, Sendable {
        public enum Kind: Sendable {
            case user(String)
            case coach(String)
            case proposal(CoachProposal)
            /// A failed turn, with the message text that can be retried.
            case failure(message: String, retryText: String)
        }

        public let id: UUID
        public var kind: Kind

        init(_ kind: Kind) {
            self.id = UUID()
            self.kind = kind
        }
    }

    public private(set) var transcript: [Entry] = []
    /// The in-flight coach reply, accumulated from `textDelta`s. Rendered in a reserved slot;
    /// folded into `transcript` on `finishedTurn`.
    public private(set) var streamingText = ""
    public private(set) var isResponding = false
    /// The most recent proposal, for the UI's "Review & apply" flow.
    public private(set) var latestProposal: CoachProposal?

    public let intent: CoachIntent

    private let session: any CoachSession
    private var turnTask: Task<Void, Never>?

    /// Fails only if the engine can't open a session (callers check `engine.availability`
    /// first and route to the degradation state instead).
    public init(engine: any CoachEngine, intent: CoachIntent, context: CoachContext) throws {
        self.intent = intent
        self.session = try engine.makeSession(intent: intent, context: context)
    }

    /// Send the user's message and stream the coach's reply into observable state.
    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        transcript.append(Entry(.user(trimmed)))
        beginTurn(sending: trimmed)
    }

    /// Re-send the message from a failed turn (the failure entry is replaced by the retry).
    public func retry(_ entry: Entry) {
        guard case let .failure(_, retryText) = entry.kind, !isResponding else { return }
        transcript.removeAll { $0.id == entry.id }
        beginTurn(sending: retryText)
    }

    /// Abandon the in-flight turn (sheet dismissed). Safe to call at any time.
    public func cancel() {
        turnTask?.cancel()
        session.cancel()
        isResponding = false
    }

    private func beginTurn(sending text: String) {
        isResponding = true
        streamingText = ""
        turnTask = Task { [weak self, session] in
            do {
                for try await event in session.send(CoachMessage(text: text)) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(event)
                }
                self?.finishTurn()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.failTurn(retryText: text, error: error)
            }
        }
    }

    private func handle(_ event: CoachEvent) {
        switch event {
        case let .textDelta(delta):
            streamingText += delta
        case let .proposal(proposal):
            // Prose before the proposal becomes its own entry so the card lands between
            // sentences the way the coach said them.
            foldStreamingText()
            latestProposal = proposal
            transcript.append(Entry(.proposal(proposal)))
        case .finishedTurn:
            finishTurn()
        }
    }

    private func finishTurn() {
        foldStreamingText()
        isResponding = false
    }

    private func failTurn(retryText: String, error: Error) {
        foldStreamingText()
        transcript.append(Entry(.failure(
            message: "The coach couldn't respond. \(error.localizedDescription)",
            retryText: retryText
        )))
        isResponding = false
    }

    private func foldStreamingText() {
        let text = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { transcript.append(Entry(.coach(text))) }
        streamingText = ""
    }
}
