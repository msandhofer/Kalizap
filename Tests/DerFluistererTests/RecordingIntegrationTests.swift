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

// MARK: - Mock Audio Recorder with Stream

final class MockAudioRecorderForIntegration: RecordingControlling, @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
    private var collectedChunks: [AudioChunk] = []

    func startRecording() async throws {
        startCalled = true
        collectedChunks = []
    }

    func stopAndCollectBuffer() async -> CollectedAudioBuffer {
        stopCalled = true
        let samples = collectedChunks.flatMap { $0.samples }
        let duration = collectedChunks.reduce(0.0) { $0 + $1.duration }
        return CollectedAudioBuffer(
            samples: samples,
            sampleRate: 16000,
            totalDuration: duration
        )
    }

    func sendChunk(_ chunk: AudioChunk) {
        collectedChunks.append(chunk)
    }
}

// MARK: - Mock Transcription Handler

final class MockTranscriptionHandler: TranscriptionHandling, @unchecked Sendable {
    var lastBuffer: CollectedAudioBuffer?
    var lastConfig: TranscriptionConfig?
    var resultText: String = "Hallo Welt"
    var transcribeCalled = false

    func transcribe(buffer: CollectedAudioBuffer, config: TranscriptionConfig) async throws -> FinalTranscription {
        transcribeCalled = true
        lastBuffer = buffer
        lastConfig = config
        return FinalTranscription(text: resultText, segments: [], processingTime: .milliseconds(100))
    }
}

// MARK: - Recording Coordinator Integration Tests

@Suite("RecordingCoordinator — Integration")
struct RecordingCoordinatorIntegrationTests {

    @MainActor
    private func makeCoordinator(
        hotkeySource: MockHotkeySource,
        recorder: MockAudioRecorderForIntegration,
        soundsEnabled: Bool = true,
        transcriptionHandler: MockTranscriptionHandler? = nil
    ) -> (RecordingCoordinator, MockSoundBackend) {
        let soundBackend = MockSoundBackend()
        let soundPlayer = SoundPlayer(backend: soundBackend, soundsEnabled: soundsEnabled)
        let viewModel = RecordingViewModel()
        let coordinator = RecordingCoordinator(
            hotkeyEvents: hotkeySource.events,
            recorder: recorder,
            soundPlayer: soundPlayer,
            viewModel: viewModel,
            transcriptionHandler: transcriptionHandler
        )
        return (coordinator, soundBackend)
    }

    @Test("hotkey started triggers recording + sound + viewmodel")
    @MainActor
    func hotkeyStartTriggersAll() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let (coordinator, soundBackend) = makeCoordinator(hotkeySource: hotkeySource, recorder: recorder)

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.startCalled)
        #expect(coordinator.viewModel.isRecording)
        #expect(soundBackend.playedSounds.contains(.recordingStarted))

        hotkeySource.finish()
        task.cancel()
    }

    @Test("hotkey stopped triggers stop recording + sound + viewmodel")
    @MainActor
    func hotkeyStopTriggersAll() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let (coordinator, soundBackend) = makeCoordinator(hotkeySource: hotkeySource, recorder: recorder)

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.stopCalled)
        #expect(!coordinator.viewModel.isRecording)
        #expect(soundBackend.playedSounds.contains(.recordingStopped))

        hotkeySource.finish()
        task.cancel()
    }

    @Test("sounds disabled skips sound playback")
    @MainActor
    func soundsDisabled() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let (coordinator, soundBackend) = makeCoordinator(
            hotkeySource: hotkeySource, recorder: recorder, soundsEnabled: false
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

    @Test("after stop, audio buffer is collected and transcribed")
    @MainActor
    func transcriptionAfterStop() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let handler = MockTranscriptionHandler()
        let (coordinator, _) = makeCoordinator(
            hotkeySource: hotkeySource, recorder: recorder, transcriptionHandler: handler
        )

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        recorder.sendChunk(makeTestChunk(samples: [0.1, 0.2, 0.3]))
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(handler.transcribeCalled)
        #expect(handler.lastBuffer?.samples == [0.1, 0.2, 0.3])

        hotkeySource.finish()
        task.cancel()
    }

    @Test("transcription result is stored in lastTranscription")
    @MainActor
    func transcriptionResultStored() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let handler = MockTranscriptionHandler()
        handler.resultText = "Das ist ein Test"
        let (coordinator, _) = makeCoordinator(
            hotkeySource: hotkeySource, recorder: recorder, transcriptionHandler: handler
        )

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        recorder.sendChunk(makeTestChunk(samples: [0.5]))

        hotkeySource.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(coordinator.lastTranscription?.text == "Das ist ein Test")

        hotkeySource.finish()
        task.cancel()
    }

    @Test("no transcription handler means no transcription attempt")
    @MainActor
    func noHandlerNoTranscription() async {
        let hotkeySource = MockHotkeySource()
        let recorder = MockAudioRecorderForIntegration()
        let (coordinator, _) = makeCoordinator(
            hotkeySource: hotkeySource, recorder: recorder, transcriptionHandler: nil
        )

        let task = Task { await coordinator.run() }
        try? await Task.sleep(for: .milliseconds(50))

        hotkeySource.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        hotkeySource.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.lastTranscription == nil)

        hotkeySource.finish()
        task.cancel()
    }
}
