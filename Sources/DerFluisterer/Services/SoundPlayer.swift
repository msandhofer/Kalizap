import Foundation

public enum SoundEffect: Sendable, Equatable {
    case recordingStarted
    case recordingStopped
}

public protocol SoundBackend: Sendable {
    func play(_ sound: SoundEffect)
}

public final class SoundPlayer: @unchecked Sendable {
    private let backend: SoundBackend
    public var soundsEnabled: Bool

    public init(backend: SoundBackend, soundsEnabled: Bool) {
        self.backend = backend
        self.soundsEnabled = soundsEnabled
    }

    public func playRecordingStarted() {
        guard soundsEnabled else { return }
        backend.play(.recordingStarted)
    }

    public func playRecordingStopped() {
        guard soundsEnabled else { return }
        backend.play(.recordingStopped)
    }
}

extension SoundPlayer: SoundPlaying {
    public func playStartSound() async {
        playRecordingStarted()
    }

    public func playStopSound() async {
        playRecordingStopped()
    }
}
