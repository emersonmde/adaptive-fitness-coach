import Foundation
import WatchKit

/// Plays the run/walk/complete haptics. The whole product can be followed by feel alone (N5):
/// the user runs when they feel the run buzz, walks when they feel the walk buzz.
@MainActor
struct HapticManager {
    private let device = WKInterfaceDevice.current()

    /// → Run: a sharp double tap. Two `.notification` haptics in quick succession read as
    /// distinctly "go" versus the single walk haptic, even mid-stride without looking.
    func playRunTransition() {
        device.play(.notification)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            device.play(.notification)
        }
    }

    /// → Walk: a single haptic, clearly distinct from the run double-tap. The design calls for
    /// "single long, soft"; watchOS exposes no true long/soft `WKHapticType`, so `.directionDown`
    /// is the closest single, gentler-reading cue. Revisit on-device against `.stop`/`.retry`.
    func playWalkTransition() {
        device.play(.directionDown)
    }

    /// Session finished — the standard success haptic.
    func playComplete() {
        device.play(.success)
    }

    /// Fire the haptic appropriate to a phase transition.
    func play(for transition: TransitionEventKind) {
        switch transition {
        case .toRun: playRunTransition()
        case .toWalk: playWalkTransition()
        }
    }
}

/// Which direction a transition went, for haptic selection.
enum TransitionEventKind {
    case toRun
    case toWalk
}
