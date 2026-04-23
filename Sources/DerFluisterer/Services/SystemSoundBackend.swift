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

    public func prewarm() {
        // Play the start sound silently to trigger a CoreAudio output-path wake-up.
        // Volume 0 ensures the user hears nothing; the HAL/coreaudiod still performs
        // the full DAC/codec activation, so the next real play() call is warm.
        guard let sound = NSSound(named: "Tink") else { return }
        sound.volume = 0
        sound.play()
    }
}
