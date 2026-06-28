import Foundation

/// The biomechanical family a strength movement belongs to.
///
/// Unused by P1's static sequencing, but it ships now because it is the key P2's IMU
/// heuristics group by: "wrist tracks load" archetypes (press/overheadPress/row/curl) get a
/// velocity-loss read, `isometric` gets a stability-envelope read, and `stationary` torso work
/// (e.g. a goblet squat where the wrist barely moves) falls back to set-outcome only — never a
/// fabricated signal (N6). Grouping by a handful of archetypes, rather than one model per
/// exercise, is a deliberate PRD §5 decision.
public enum MovementArchetype: String, Codable, Sendable, CaseIterable, Hashable {
    case press
    case overheadPress
    case row
    case curl
    case isometric
    case stationary
}
