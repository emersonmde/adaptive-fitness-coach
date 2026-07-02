import Foundation

/// Detects "the user started running" from a live cadence stream (steps per minute).
///
/// Running cadence sits well above walking even at a very slow jog (~140+ spm vs ~100–120
/// walking; brisk walking peaks ~130–135), so a sustained threshold crossing is a reliable
/// gait switch. The debounce (`sustainDuration`) rejects brief spikes (jogging three steps
/// across a street), and `staleAfter` resets the streak across sensor gaps so two unrelated
/// bursts can't add up to a trigger.
///
/// Pure and clock-free: the caller supplies timestamps (session-elapsed seconds), so it is
/// deterministic and testable. One-shot — after firing it stays quiet until `reset()`.
public struct RunningCadenceDetector: Sendable {
    /// Cadence at/above this counts as running (steps per minute).
    public let threshold: Double
    /// Seconds the cadence must stay at/above `threshold` before firing.
    public let sustainDuration: TimeInterval
    /// A gap between samples longer than this breaks the streak (sensor dropout).
    public let staleAfter: TimeInterval

    private var streakStart: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var hasFired = false

    public init(threshold: Double = 140, sustainDuration: TimeInterval = 10, staleAfter: TimeInterval = 6) {
        self.threshold = threshold
        self.sustainDuration = sustainDuration
        self.staleAfter = staleAfter
    }

    /// Feed one cadence sample taken at `time` (session-elapsed seconds, monotonic).
    /// Returns true exactly once, on the sample that completes a sustained running streak.
    public mutating func update(cadence: Double, at time: TimeInterval) -> Bool {
        guard !hasFired else { return false }

        // A dropout breaks the streak: the gap says nothing about the gait during it.
        if let last = lastSampleTime, time - last > staleAfter {
            streakStart = nil
        }
        lastSampleTime = time

        guard cadence >= threshold else {
            streakStart = nil
            return false
        }

        let start = streakStart ?? time
        streakStart = start

        if time - start >= sustainDuration {
            hasFired = true
            return true
        }
        return false
    }

    /// Re-arm the detector (e.g. if a future flow wants to detect a second run start).
    public mutating func reset() {
        streakStart = nil
        lastSampleTime = nil
        hasFired = false
    }
}
