import Testing
import Foundation
@testable import DerFluisterer

// MARK: - Mock Hotkey Source

final class MockHotkeySource: @unchecked Sendable {
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    var events: AsyncStream<HotkeyEvent> {
        AsyncStream { self.continuation = $0 }
    }

    func send(_ event: HotkeyEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }
}

// MARK: - Mock Audio Recorder

final class MockAudioRecorderForIntegration: RecordingControlling, @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
    var state: AudioRecorderState = .idle

    func startRecording() async throws {
        startCalled = true
        state = .recording
    }

    func stopRecording() async {
        stopCalled = true
        state = .idle
    }
}

// MARK: - Recording Coordinator Integration Tests

@Suite("RecordingCoordinator — Integration")
struct RecordingCoordinatorIntegrationTests {

    @Test("hotkey started triggers recording + sound + viewmodel")
    @MainActor
    func hotkeyStartTriggersAll() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let soundBackend = MockSoundBackend()
        let soundPlayer = SoundPlayer(backend: soundBackend, soundsEnabled: true)
        let viewModel = RecordingViewModel()

        let coordinator = RecordingCoordinator(
            hotkeyEvents: hotkeySource.events,
            recorder: recorder,
            soundPlayer: soundPlayer,
            viewModel: viewModel
        )

        let task = Task { await coordinator.run() }

        // Give the coordinator time to start listening
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.startCalled)
        #expect(viewModel.isRecording)
        #expect(soundBackend.playedSounds.contains(.recordingStarted))

        hotkeySource.finish()
        task.cancel()
    }

    @Test("hotkey stopped triggers stop recording + sound + viewmodel")
    @MainActor
    func hotkeyStopTriggersAll() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let soundBackend = MockSoundBackend()
        let soundPlayer = SoundPlayer(backend: soundBackend, soundsEnabled: true)
        let viewModel = RecordingViewModel()

        let coordinator = RecordingCoordinator(
            hotkeyEvents: hotkeySource.events,
            recorder: recorder,
            soundPlayer: soundPlayer,
            viewModel: viewModel
        )

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.stopCalled)
        #expect(!viewModel.isRecording)
        #expect(soundBackend.playedSounds.contains(.recordingStopped))

        hotkeySource.finish()
        task.cancel()
    }

    @Test("sounds disabled skips sound playback")
    @MainActor
    func soundsDisabled() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let soundBackend = MockSoundBackend()
        let soundPlayer = SoundPlayer(backend: soundBackend, soundsEnabled: false)
        let viewModel = RecordingViewModel()

        let coordinator = RecordingCoordinator(
            hotkeyEvents: hotkeySource.events,
            recorder: recorder,
            soundPlayer: soundPlayer,
            viewModel: viewModel
        )

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.startCalled)
        #expect(soundBackend.playedSounds.isEmpty)

        hotkeySource.finish()
        task.cancel()
    }
}
