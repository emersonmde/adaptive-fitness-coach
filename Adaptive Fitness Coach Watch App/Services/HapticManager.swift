import Foundation
import WatchKit

/// Plays the run/walk/complete haptics. The whole product can be followed by feel alone (N5):
/// the user runs when they feel the run buzz, walks when they feel the walk buzz.
@MainActor
struct HapticManager {
    private let device = WKInterfaceDevice.current()

    /// Play a burst of haptics spread over enough wall time to register mid-stride. Real-run
    /// feedback: single or tightly-spaced taps disappear under footstrike vibration, so
    /// transitions use three pulses ~350ms apart (~a full stride cycle each — at 160+ spm at
    /// least one lands between footfalls).
    private func burst(_ type: WKHapticType, count: Int, spacingMs: Int = 350) {
        device.play(type)
        guard count > 1 else { return }
        Task {
            for _ in 1..<count {
                try? await Task.sleep(for: .milliseconds(spacingMs))
                device.play(type)
            }
        }
    }

    /// → Run: a triple sharp tap — unmistakably "go", even mid-stride without looking.
    func playRunTransition() {
        burst(.notification, count: 3)
    }

    /// → Walk: a triple descending cue, spaced like the run burst but a clearly different
    /// character (`.directionDown` vs `.notification`), so run/walk stay distinguishable by
    /// feel alone (N5). The old single tap was too easy to miss while running.
    func playWalkTransition() {
        burst(.directionDown, count: 3)
    }

    /// → Still running after a walk cue (cadence-verified): a gentle two-pulse reminder,
    /// shorter than the transition burst so it reads as "hey, walk" rather than a new phase.
    func playWalkNudge() {
        burst(.directionDown, count: 2)
    }

    /// Session finished — the standard success haptic.
    func playComplete() {
        device.play(.success)
    }

    /// → A set is done within the same exercise: a light single tap to confirm without looking.
    func playSetComplete() {
        device.play(.click)
    }

    /// → Moving to the next exercise: a distinct double tap so the change of movement registers
    /// by feel, like the run/walk transition does (N5).
    func playExerciseChange() {
        device.play(.notification)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            device.play(.notification)
        }
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
