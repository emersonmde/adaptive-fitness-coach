import Foundation

/// The provider-agnostic seam between the coach UI and whatever model runs the conversation —
/// the `WorkoutBackend` pattern lifted to the AI layer (P3).
///
/// The phone app talks only to these types; the production engine (FoundationModels: on-device /
/// Private Cloud Compute) and the deterministic `ScriptedCoachEngine` both conform, and a future
/// Claude-API or user-API-key engine can replace them without touching the UI or this package.
/// The cross-provider contract is deliberately small: messages in, a stream of `CoachEvent`s out,
/// of which at most one per turn is a *validated* `CoachProposal`. Tool use, structured-output
/// schemas, and prompt wire formats stay engine-internal so providers never have to agree on them.

/// What the user opened the coach to do. Selects the system instructions and context; the
/// conversation code path is identical across intents.
public enum CoachIntent: Sendable, Hashable {
    /// Build a plan from nothing: intake (equipment → starting point → goals) then propose.
    case buildNewPlan
    /// Rework one routine (analyze, adjust for new circumstances). Names stay stable so the
    /// store's name-merge grafts progression back on apply.
    case reviseRoutine(Routine.ID)
    /// Analyze/rework the whole week — may edit existing routines or add new ones.
    case reviseAll
}

/// The read-only snapshot of the user's current state handed to the engine at session start.
/// Built by `CoachContextBuilder`; empty for `.buildNewPlan`.
public struct CoachContext: Sendable, Hashable {
    /// Current routines as `RoutineExchange` JSON (the schema the model also proposes in).
    public var routinesJSON: String?
    /// Human-readable earned progression state (seeds, calibration, current loads). The coach
    /// must *see* progression to reason about experience, but the output schema deliberately
    /// omits it — the model is structurally unable to write what it can read here.
    public var progressionSummary: String?
    /// For `.reviseRoutine`, the name of the routine under discussion.
    public var focusRoutineName: String?

    public init(
        routinesJSON: String? = nil,
        progressionSummary: String? = nil,
        focusRoutineName: String? = nil
    ) {
        self.routinesJSON = routinesJSON
        self.progressionSummary = progressionSummary
        self.focusRoutineName = focusRoutineName
    }

    public static let empty = CoachContext()
}

/// One conversational message. Content is an array so P4 can attach images (meal photos,
/// receipts) to the same seam; P3 only ever sends a single `.text` part.
public struct CoachMessage: Sendable, Hashable {
    public enum Role: String, Sendable, Hashable {
        case user
        case coach
    }

    public enum Content: Sendable, Hashable {
        case text(String)
        /// Encoded image data (P4 extension point — unused in P3).
        case image(Data)
    }

    public var role: Role
    public var content: [Content]

    public init(role: Role = .user, content: [Content]) {
        self.role = role
        self.content = content
    }

    public init(text: String, role: Role = .user) {
        self.init(role: role, content: [.text(text)])
    }

    /// The concatenated text parts (images excluded).
    public var text: String {
        content.compactMap { if case let .text(t) = $0 { t } else { nil } }.joined()
    }
}

/// What an engine emits while responding to one `send`.
public enum CoachEvent: Sendable {
    /// A chunk of streamed persona prose. Append to the in-flight coach message.
    case textDelta(String)
    /// The full in-flight reply, REPLACING everything streamed so far this turn. For
    /// providers whose cumulative snapshots can rewrite earlier content (seen around tool
    /// calls) — append-only deltas would garble or duplicate the text.
    case textReplace(String)
    /// A validated plan draft. Engines validate raw model output through
    /// `CoachProposalValidator` before emitting — the UI never sees an unvalidated plan.
    case proposal(CoachProposal)
    /// The turn is complete; the stream finishes after this.
    case finishedTurn
}

/// Whether an engine can run right now, with an honest, user-facing reason when it can't
/// (device unsupported, Apple Intelligence off, model downloading, offline…). The UI shows
/// the reason verbatim and routes to the manual Claude-app loop as the fallback (N6).
public enum CoachAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// One live conversation. Created per sheet presentation; conversations are ephemeral —
/// the durable artifact is the routine set the user applies.
public protocol CoachSession: AnyObject, Sendable {
    /// Send a message and stream the coach's response. Events arrive in order; the stream
    /// ends after `.finishedTurn` (or throws — the conversation surfaces a retryable error).
    func send(_ message: CoachMessage) -> AsyncThrowingStream<CoachEvent, Error>
    /// Abandon the in-flight response (sheet dismissed, user cancelled).
    func cancel()
}

/// A model backend that can host coach sessions.
public protocol CoachEngine: Sendable {
    var availability: CoachAvailability { get }
    func makeSession(intent: CoachIntent, context: CoachContext) throws -> any CoachSession
}
