import Testing
import Foundation
@testable import DerFluisterer

@Suite("SoundPlayer")
struct SoundPlayerTests {

    @Test("plays start sound when sounds enabled")
    func playStartSound() {
        let backend = MockSoundBackend()
        let player = SoundPlayer(backend: backend, soundsEnabled: true)
        player.playRecordingStarted()
        #expect(backend.playedSounds == [.recordingStarted])
    }

    @Test("plays stop sound when sounds enabled")
    func playStopSound() {
        let backend = MockSoundBackend()
        let player = SoundPlayer(backend: backend, soundsEnabled: true)
        player.playRecordingStopped()
        #expect(backend.playedSounds == [.recordingStopped])
    }

    @Test("does not play when sounds disabled")
    func soundsDisabled() {
        let backend = MockSoundBackend()
        let player = SoundPlayer(backend: backend, soundsEnabled: false)
        player.playRecordingStarted()
        player.playRecordingStopped()
        #expect(backend.playedSounds.isEmpty)
    }

    @Test("toggling sounds enabled at runtime")
    func toggleSounds() {
        let backend = MockSoundBackend()
        let enabled = SendableBox(false)
        let player = SoundPlayer(backend: backend, isEnabled: { enabled.value })
        player.playRecordingStarted()
        #expect(backend.playedSounds.isEmpty)

        enabled.set(true)
        player.playRecordingStarted()
        #expect(backend.playedSounds == [.recordingStarted])
    }
}
