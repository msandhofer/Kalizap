import AppKit

public struct SystemSoundBackend: SoundBackend {
    public init() {}

    public func play(_ sound: SoundEffect) {
        let name: NSSound.Name
        switch sound {
        case .recordingStarted:
            name = "Tink"
        case .recordingStopped:
            name = "Pop"
        }
        NSSound(named: name)?.play()
    }
}
