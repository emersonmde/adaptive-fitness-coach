import Foundation

/// A library catalog entry: one movement the app knows how to coach, with conservative seed
/// defaults. Authored content (see `ExerciseLibrary`), not a per-user record. The user picks
/// these into a routine and may adjust the prescription; the entry itself never changes.
public struct Exercise: Codable, Sendable, Hashable, Identifiable {
    /// Stable slug used to reference this entry from a routine and over WatchConnectivity
    /// (e.g. `"db_bench_press"`). Because the catalog is shared by both apps, only the id
    /// travels in the sync payload — never the whole entry.
    public let id: String
    public var name: String
    /// Muscle / pattern tags for grouping in the library UI (e.g. `["chest", "triceps"]`).
    public var muscleTags: [String]
    /// Biomechanical family — the forward hook P2's IMU heuristics key off (see `MovementArchetype`).
    public var archetype: MovementArchetype
    /// One-line "good for" copy shown in the library (the movement's benefit / why you'd do it).
    public var goodFor: String
    /// 1–2 sentences on **how to perform** the movement — the help-screen description shown on the
    /// watch and in the iOS info sheet, alongside the form demo (the future home of an animation).
    public var howTo: String
    /// Short coaching cues ("brace your core", "control the lowering"), shown as bullets in the
    /// detailed info. May be empty.
    public var tips: [String]
    /// Form demonstration reference (an SF Symbol placeholder in P1).
    public var formDemo: FormDemo
    /// Conservative default number of sets.
    public var defaultSets: Int
    /// Whether the movement is counted in reps (with an optional load) or held for time.
    public var kind: ExerciseKind

    public init(
        id: String,
        name: String,
        muscleTags: [String],
        archetype: MovementArchetype,
        goodFor: String,
        howTo: String = "",
        tips: [String] = [],
        formDemo: FormDemo,
        defaultSets: Int,
        kind: ExerciseKind
    ) {
        self.id = id
        self.name = name
        self.muscleTags = muscleTags
        self.archetype = archetype
        self.goodFor = goodFor
        self.howTo = howTo
        self.tips = tips
        self.formDemo = formDemo
        self.defaultSets = defaultSets
        self.kind = kind
    }
}

/// How an exercise is prescribed: counted reps (optionally loaded) or an isometric hold.
///
/// Modeled as an enum rather than a bag of optionals so an illegal combination — a planked
/// "rep count", a curl with a "hold time" — is simply unrepresentable.
public enum ExerciseKind: Codable, Sendable, Hashable {
    /// Rep-based work. `seedWeight == nil` means bodyweight (e.g. a push-up).
    case reps(defaultReps: Int, seedWeight: Weight?)
    /// Isometric hold for a duration (e.g. a plank). Bodyweight by definition.
    case hold(defaultSeconds: TimeInterval)

    /// True for the isometric (held-for-time) prescription — the variant that shows a hold
    /// timer instead of a rep/weight card on the watch.
    public var isHold: Bool {
        if case .hold = self { return true }
        return false
    }
}
