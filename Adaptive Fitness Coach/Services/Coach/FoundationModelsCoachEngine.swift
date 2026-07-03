import Foundation
import FoundationModels
import AdaptiveCore

/// The production `CoachEngine`: Apple's Foundation Models framework. Defaults to Private
/// Cloud Compute (the larger Apple server model — 32K context, no API keys, free tier) and
/// falls back to the on-device model when PCC isn't reachable; if neither is available the
/// UI gets an honest reason and routes to the manual Claude-app loop (N6).
///
/// Swapping providers later (Claude API, Gemini via Firebase, user API keys) means another
/// `CoachEngine` conformance in `CoachEngineProvider` — nothing downstream changes.
struct FoundationModelsCoachEngine: CoachEngine {

    var availability: CoachAvailability {
        // The simulator can't run Apple Intelligence — FoundationModels calls there hang or
        // trip framework assertions (observed: SIGTRAP inside LanguageModelSession creation).
        // The sim path is `-simulateCoach`; the real engine honestly reports unavailable.
        #if targetEnvironment(simulator)
        return .unavailable(reason: "The coach needs Apple Intelligence on a real device. In the simulator, launch with -simulateCoach. You can also round-trip routines through the Claude app from the Coach menu.")
        #else
        // PCC without its entitlement is a FATAL ERROR, not .unavailable (found by the P4
        // LookupLab device spike) — never touch the type unless the profile carries the grant.
        if PCCEntitlement.isGranted,
           case .available = PrivateCloudComputeLanguageModel().availability { return .available }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        }
        #endif
    }

    func makeSession(intent: CoachIntent, context: CoachContext) throws -> any CoachSession {
        #if targetEnvironment(simulator)
        throw CocoaError(.featureUnsupported)
        #else
        let instructions = CoachPromptBuilder.instructions(intent: intent, context: context)
            + "\n\n" + Self.toolInstructions

        // One sink per session: the tool validates and pushes proposals; the session forwards
        // them into whichever turn's event stream is live.
        let sink = ProposalSink()
        let tool = ProposePlanTool { sink.deliver($0) }

        // Prefer PCC (bigger model, reasoning) when the build is entitled to it; degrade to
        // on-device rather than failing — a weaker coach beats no coach, and the seam hides
        // the choice from the UI.
        let session: LanguageModelSession
        if PCCEntitlement.isGranted,
           case .available = PrivateCloudComputeLanguageModel().availability {
            session = LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(), tools: [tool], instructions: instructions
            )
        } else if SystemLanguageModel.default.isAvailable {
            session = LanguageModelSession(model: SystemLanguageModel.default, tools: [tool], instructions: instructions)
        } else {
            throw CocoaError(.featureUnsupported)
        }
        session.prewarm()
        return FoundationModelsCoachSession(session: session, proposals: sink)
        #endif
    }

    /// Engine-specific addendum to the shared instructions: how the plan physically reaches
    /// the user in *this* harness.
    private static let toolInstructions = """
    When you are ready to propose the plan (or a revision), call the propose_plan tool with \
    the complete set of routines. The tool renders them as cards in the app — never write the \
    plan out as text or JSON in your reply.
    """

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        let base: String
        switch reason {
        case .deviceNotEligible:
            base = "This iPhone doesn't support Apple Intelligence, which powers the coach."
        case .appleIntelligenceNotEnabled:
            base = "Turn on Apple Intelligence in Settings to use the coach."
        case .modelNotReady:
            base = "The Apple Intelligence model is still getting ready — try again in a bit."
        @unknown default:
            base = "Apple Intelligence isn't available right now."
        }
        return base + " You can still round-trip routines through the Claude app from the Coach menu."
    }
}

/// Thread-safe handoff from tool calls (which run wherever the framework schedules them) to
/// the current turn's event continuation.
private final class ProposalSink: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((CoachProposal) -> Void)?

    func onProposal(_ handler: @escaping (CoachProposal) -> Void) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    func deliver(_ proposal: CoachProposal) {
        lock.lock(); let handler = handler; lock.unlock()
        handler?(proposal)
    }
}

/// Adapts one `LanguageModelSession` to the `CoachSession` seam: streams cumulative snapshots
/// as text deltas and forwards tool-validated proposals into the same event stream.
private final class FoundationModelsCoachSession: CoachSession, @unchecked Sendable {
    private let session: LanguageModelSession
    private let proposals: ProposalSink
    private let lock = NSLock()
    private var turnTask: Task<Void, Never>?

    init(session: LanguageModelSession, proposals: ProposalSink) {
        self.session = session
        self.proposals = proposals
    }

    func send(_ message: CoachMessage) -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            proposals.onProposal { continuation.yield(.proposal($0)) }
            let task = Task { [session] in
                do {
                    // Snapshots are cumulative; the seam speaks deltas.
                    var streamed = ""
                    for try await snapshot in session.streamResponse(to: message.text) {
                        let full = snapshot.content
                        if full.count > streamed.count {
                            continuation.yield(.textDelta(String(full.dropFirst(streamed.count))))
                            streamed = full
                        }
                    }
                    continuation.yield(.finishedTurn)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            lock.lock(); turnTask = task; lock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel() {
        lock.lock(); let task = turnTask; lock.unlock()
        task?.cancel()
    }
}
