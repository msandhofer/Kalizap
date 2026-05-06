import Foundation

public enum SoundEffect: Sendable, Equatable {
    case recordingStarted
    case recordingStopped
}

public protocol SoundBackend: Sendable {
    func play(_ sound: SoundEffect)
    /// Play the start-sound silently (volume 0) to warm up the CoreAudio output path.
    func prewarm()
}

public final class SoundPlayer: SoundPlaying, @unchecked Sendable {
    private let backend: SoundBackend
    private let isEnabled: () -> Bool

    public init(backend: SoundBackend, soundsEnabled: Bool) {
        self.backend = backend
        self.isEnabled = { soundsEnabled }
    }

    public init(backend: SoundBackend, isEnabled: @escaping () -> Bool) {
        self.backend = backend
        self.isEnabled = isEnabled
    }

    // MARK: - SoundPlaying (async, used by DictationPipeline)

    public func playStartSound() async {
        guard isEnabled() else { return }
        backend.play(.recordingStarted)
    }

    public func playStopSound() async {
        guard isEnabled() else { return }
        backend.play(.recordingStopped)
    }

    public func prewarm() async {
        // Prewarm is intentionally unconditional of isEnabled: its purpose is to
        // warm the CoreAudio output path so the next real play is fast. The user
        // hears nothing (volume 0).
        backend.prewarm()
    }

    // MARK: - Synchronous (used by RecordingCoordinator)

    public func playRecordingStarted() {
        guard isEnabled() else { return }
        backend.play(.recordingStarted)
    }

    public func playRecordingStopped() {
        guard isEnabled() else { return }
        backend.play(.recordingStopped)
    }
}
