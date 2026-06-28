import Foundation

/// A reference to an exercise's form demonstration, kept abstract so the asset can change
/// without touching the model or the render call sites.
///
/// P1 ships only `.symbol` — an SF Symbol "figure" pose used as a static diagram placeholder.
/// `.diagram` and `.animation` are reserved for the eventual real assets (a static illustration,
/// then a looping/tap-to-play character demo); swapping a library entry from `.symbol` to one of
/// those is a pure data change the views already know how to read.
public enum FormDemo: Codable, Sendable, Hashable {
    /// An SF Symbol name (e.g. `"figure.strengthtraining.traditional"`) — the P1 placeholder.
    case symbol(String)
    /// A named static illustration asset — future fidelity step.
    case diagram(String)
    /// A named looping/tap-to-play animation asset — future fidelity step.
    case animation(String)
}
