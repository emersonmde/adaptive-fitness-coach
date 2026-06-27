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
    }

    /// Current payload schema version. Bump when the routine encoding changes incompatibly.
    public static let currentVersion = 1

    public enum CodecError: Error, Equatable {
        case missingRoutines
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
}
