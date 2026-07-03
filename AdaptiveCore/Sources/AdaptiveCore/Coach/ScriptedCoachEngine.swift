import Foundation

/// The deterministic `CoachEngine`: plays back an authored script of turns instead of calling
/// a model — the `SimulatedWorkoutBackend` pattern for the coach. Used by AdaptiveCore unit
/// tests (drive `CoachConversation` without a model) and by the phone's `-simulateCoach`
/// launch arg (demo/UI-test the whole flow in the simulator, where Apple Intelligence can't
/// be granted).
public struct ScriptedCoachEngine: CoachEngine {

    /// One coach reply: prose (streamed in word chunks), optionally followed by a proposal.
    public struct Turn: Sendable {
        public var text: String
        public var proposal: CoachProposal?
        /// Thrown instead of responding — for testing the failure/retry path.
        public var error: Error?

        public init(text: String, proposal: CoachProposal? = nil, error: Error? = nil) {
            self.text = text
            self.proposal = proposal
            self.error = error
        }
    }

    public var availability: CoachAvailability
    /// Delay between streamed chunks — nil (default) for instant tests; the simulator demo
    /// uses a small delay so streaming is visible.
    public var deltaDelay: Duration?

    private let turns: [Turn]

    public init(turns: [Turn], availability: CoachAvailability = .available, deltaDelay: Duration? = nil) {
        self.turns = turns
        self.availability = availability
        self.deltaDelay = deltaDelay
    }

    public func makeSession(intent: CoachIntent, context: CoachContext) throws -> any CoachSession {
        guard availability.isAvailable else {
            throw CocoaError(.featureUnsupported)
        }
        return ScriptedCoachSession(turns: turns, deltaDelay: deltaDelay)
    }
}

/// Replays scripted turns in order; sends past the end of the script repeat the last turn
/// (so a demo can absorb extra user messages without wedging — principle 13).
final class ScriptedCoachSession: CoachSession, @unchecked Sendable {
    private let turns: [ScriptedCoachEngine.Turn]
    private let deltaDelay: Duration?
    private let lock = NSLock()
    private var nextIndex = 0

    init(turns: [ScriptedCoachEngine.Turn], deltaDelay: Duration?) {
        self.turns = turns
        self.deltaDelay = deltaDelay
    }

    func send(_ message: CoachMessage) -> AsyncThrowingStream<CoachEvent, Error> {
        let turn: ScriptedCoachEngine.Turn? = {
            lock.lock()
            defer { lock.unlock() }
            guard !turns.isEmpty else { return nil }
            let turn = turns[min(nextIndex, turns.count - 1)]
            nextIndex += 1
            return turn
        }()

        return AsyncThrowingStream { continuation in
            let task = Task { [deltaDelay] in
                guard let turn else {
                    continuation.yield(.finishedTurn)
                    continuation.finish()
                    return
                }
                if let error = turn.error {
                    continuation.finish(throwing: error)
                    return
                }
                // Stream word-by-word so the UI's streaming path is exercised for real.
                for word in turn.text.split(separator: " ", omittingEmptySubsequences: false) {
                    if Task.isCancelled { break }
                    continuation.yield(.textDelta(String(word) + " "))
                    if let deltaDelay { try? await Task.sleep(for: deltaDelay) }
                }
                if let proposal = turn.proposal, !Task.isCancelled {
                    continuation.yield(.proposal(proposal))
                }
                continuation.yield(.finishedTurn)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // In-flight streams are torn down via their continuation's onTermination when the
    // consuming task is cancelled; the scripted session holds no other live resources.
    func cancel() {}
}

// MARK: - Canned demo script

public extension ScriptedCoachEngine {
    /// The intake demo used by `-simulateCoach` and the UI tests: equipment → starting point →
    /// goals → a two-routine proposal built from real library entries (so import succeeds and
    /// applied routines behave like hand-built ones).
    static func demoIntake(deltaDelay: Duration? = nil) -> ScriptedCoachEngine {
        let plan = [
            Routine(
                name: "Coached Strength A",
                repeatDays: [.monday, .thursday],
                cards: [
                    .exercise(StrengthExerciseItem(from: ExerciseLibrary.exercise(id: "goblet_squat")!)),
                    .rest(RestCard(seconds: 90)),
                    .exercise(StrengthExerciseItem(from: ExerciseLibrary.exercise(id: "push_up")!)),
                    .rest(RestCard(seconds: 90)),
                    .exercise(StrengthExerciseItem(from: ExerciseLibrary.exercise(id: "plank")!)),
                    .rest(RestCard(seconds: 60)),
                ],
                rounds: 3
            ),
            Routine(
                name: "Coached Run",
                repeatDays: [.saturday],
                cards: [.run(RunCard(durationMinutes: 20))]
            ),
        ]
        // The sheet's static greeting asks the equipment question, so the script opens by
        // responding to that answer (starting point → goal → proposal).
        return ScriptedCoachEngine(turns: [
            Turn(text: "Good kit — plenty to work with. Where are you starting from — have you been training lately, and is anything nagging you?"),
            Turn(text: "That's a solid base. What's the goal — strength, endurance, dropping weight, just feeling better?"),
            Turn(
                text: "Here's what I'd start you on: two strength days and an easy adaptive run on the weekend. The app will adjust weights and run intervals from how you actually perform.",
                proposal: CoachProposal(
                    routines: plan,
                    summary: "Two strength days plus one adaptive run to start."
                )
            ),
            Turn(text: "Want me to adjust anything — days, length, or a different focus?"),
        ], deltaDelay: deltaDelay)
    }
}
