import Foundation

/// Pure state machine for audio activity tracking. No CoreAudio dependency,
/// fully testable. Keeps track of whether audio is currently running and
/// when it last stopped, so `isWarm` can answer "was there audio recently?"
/// within a configurable warmth window.
///
/// See docs/audio-cold-start/ for the design rationale.
public struct AudioActivityState: Sendable {
    public let warmthWindow: Duration
    public private(set) var isCurrentlyRunning: Bool
    public private(set) var lastActivityAt: ContinuousClock.Instant?

    public init(warmthWindow: Duration = .seconds(5)) {
        self.warmthWindow = warmthWindow
        self.isCurrentlyRunning = false
        self.lastActivityAt = nil
    }

    /// Record a transition reported by the listener.
    /// - If audio is running now, set `lastActivityAt = at` (so the window
    ///   starts counting from now, not from an earlier transition).
    /// - On transition `running → stopped`, also set `lastActivityAt = at`.
    public mutating func onStateChange(nowRunning: Bool, at: ContinuousClock.Instant) {
        let wasRunning = isCurrentlyRunning
        isCurrentlyRunning = nowRunning
        if nowRunning {
            lastActivityAt = at
        } else if wasRunning {
            // Transition running → stopped: remember the moment.
            lastActivityAt = at
        }
    }

    /// True if audio is currently running, or was running within the warmth window.
    public func isWarm(at: ContinuousClock.Instant) -> Bool {
        if isCurrentlyRunning { return true }
        guard let last = lastActivityAt else { return false }
        let elapsed = at - last
        return elapsed < warmthWindow
    }
}
