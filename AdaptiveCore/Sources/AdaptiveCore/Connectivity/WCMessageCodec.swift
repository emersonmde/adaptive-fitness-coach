import Foundation

/// Serializes routines for transport over WatchConnectivity's `[String: Any]` dictionaries.
///
/// Lives in the shared package so the phone (sender) and watch (receiver) encode and decode
/// with identical logic. Routines are encoded as a single JSON `Data` blob under one key,
/// alongside a schema `version` so a future format change can be detected rather than
/// silently mis-decoded.
public enum WCMessageCodec {

    /// Keys used in the transported dictionary.
    public enum Key {
        public static let routines = "routines"
        public static let version = "version"
        /// The watch → phone progression channel (a `ProgressionBatch` JSON blob).
        public static let progression = "progression"
        public static let progressionVersion = "progressionVersion"
        /// The bidirectional quick-log channel (a `QuickLogMessage` JSON blob) — live
        /// `sendMessage` round trips, with `transferUserInfo` as the offline fallback.
        public static let quickLog = "quickLog"
        public static let quickLogVersion = "quickLogVersion"
    }

    /// Current payload schema version. Bump when the routine encoding changes incompatibly.
    /// v3: `Routine` moved to a generic `cards` + `rounds` model (run/exercise/rest cards),
    /// replacing the v2 `type`/`durationMinutes`/`exercises` shape.
    /// v4: `RunCard.durationMinutes` re-scoped from *total session* to *run block* (warmup and
    /// cooldown are now separate fields). The bump makes a stale watch keep its last-known-good
    /// routines rather than reinterpret durations under the old semantics.
    /// v5: `RestCard` gained `adaptive` (heart-rate-bounded rests, default true).
    public static let currentVersion = 5

    /// Version for the independent progression channel. Versioned separately from `currentVersion`
    /// so a progression-format change never forces stale peers to reject the (unchanged) routines.
    /// v2: `ProgressionBatch` gained `runUpdates` (run/walk seed progression).
    /// v3: `ProgressionUpdate` gained `holdSeconds` (hold progression).
    /// v4: updates carry `reason` (journal); batch gained `proposals`/`runProposals`
    ///     (structural moves awaiting confirm) + `perceivedEffort`/`sessionDate`.
    public static let currentProgressionVersion = 4

    /// Version for the quick-log channel (P6). One version constant covers every message
    /// shape — the envelope enum discriminates inside the blob.
    public static let currentQuickLogVersion = 1

    public enum CodecError: Error, Equatable {
        case missingRoutines
        case missingProgression
        case missingQuickLog
        case unsupportedVersion(Int)
    }

    /// Encode routines into a dictionary suitable for `updateApplicationContext`.
    public static func encode(routines: [Routine]) throws -> [String: Any] {
        let data = try JSONEncoder().encode(routines)
        return [
            Key.routines: data,
            Key.version: currentVersion,
        ]
    }

    /// Decode routines from a received application-context dictionary.
    ///
    /// The version must equal `currentVersion` exactly (a missing version decodes as 0 and is
    /// rejected). On a version mismatch this throws so the receiver keeps its last-known-good
    /// routines rather than acting on a payload it may not understand.
    public static func decodeRoutines(from message: [String: Any]) throws -> [Routine] {
        // A version field is required and must be understood.
        let version = message[Key.version] as? Int ?? 0
        guard version == currentVersion else {
            throw CodecError.unsupportedVersion(version)
        }
        guard let data = message[Key.routines] as? Data else {
            throw CodecError.missingRoutines
        }
        return try JSONDecoder().decode([Routine].self, from: data)
    }

    // MARK: - Progression channel (watch → phone)

    /// Encode a progression batch for `transferUserInfo`. Travels under its own key + version, so it
    /// is orthogonal to the routines channel and demultiplexes by which delegate callback delivers it.
    public static func encode(progression batch: ProgressionBatch) throws -> [String: Any] {
        let data = try JSONEncoder().encode(batch)
        return [
            Key.progression: data,
            Key.progressionVersion: currentProgressionVersion,
        ]
    }

    /// Decode a progression batch. Mirrors `decodeRoutines`: the version must match exactly, and a
    /// payload without the progression key throws so a mismatched/unrelated message is ignored (N6).
    public static func decodeProgression(from message: [String: Any]) throws -> ProgressionBatch {
        let version = message[Key.progressionVersion] as? Int ?? 0
        guard version == currentProgressionVersion else {
            throw CodecError.unsupportedVersion(version)
        }
        guard let data = message[Key.progression] as? Data else {
            throw CodecError.missingProgression
        }
        return try JSONDecoder().decode(ProgressionBatch.self, from: data)
    }

    // MARK: - Quick-log channel (bidirectional, P6)

    public static func encode(quickLog message: QuickLogMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(message)
        return [
            Key.quickLog: data,
            Key.quickLogVersion: currentQuickLogVersion,
        ]
    }

    /// Same exact-version contract as the other channels: a mismatched peer's message is
    /// rejected (the sender falls back to its honest failure state) rather than mis-decoded.
    public static func decodeQuickLog(from message: [String: Any]) throws -> QuickLogMessage {
        let version = message[Key.quickLogVersion] as? Int ?? 0
        guard version == currentQuickLogVersion else {
            throw CodecError.unsupportedVersion(version)
        }
        guard let data = message[Key.quickLog] as? Data else {
            throw CodecError.missingQuickLog
        }
        return try JSONDecoder().decode(QuickLogMessage.self, from: data)
    }
}
