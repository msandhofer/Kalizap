import Testing
import Foundation
@testable import Kalizap

// MARK: - Mock Audio Engine

final class MockAudioEngine: AudioEngineProviding, @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
    var shouldThrowOnStart = false
    private var audioContinuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?

    var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            self.audioContinuation = continuation
        }
    }

    func startCapture() throws {
        if shouldThrowOnStart {
            throw AudioRecorderError.engineSetupFailed(underlying: NSError(domain: "test", code: 1))
        }
        startCalled = true
    }

    func stopCapture() {
        stopCalled = true
        audioContinuation?.finish()
    }

    func sendChunk(_ chunk: AudioChunk) {
        audioContinuation?.yield(chunk)
    }
}

// MARK: - State Machine Tests

@Suite("AudioSessionCoordinator — State Transitions")
struct AudioSessionCoordinatorStateTests {

    @Test("initial state is idle")
    func initialState() {
        let engine = MockAudioEngine()
        let coordinator = AudioSessionCoordinator(engine: engine)
        #expect(coordinator.state == .idle)
    }

    @Test("startRecording transitions to recording")
    func startTransition() async throws {
        let engine = MockAudioEngine()
        let coordinator = AudioSessionCoordinator(engine: engine)
        try await coordinator.startRecording()
        #expect(coordinator.state == .recording)
        #expect(engine.startCalled)
    }

    @Test("stopRecording transitions back to idle")
    func stopTransition() async throws {
        let engine = MockAudioEngine()
        let coordinator = AudioSessionCoordinator(engine: engine)
        try await coordinator.startRecording()
        await coordinator.stopRecording()
        #expect(coordinator.state == .idle)
        #expect(engine.stopCalled)
    }

    @Test("startRecording when already recording is ignored")
    func doubleStart() async throws {
        let engine = MockAudioEngine()
        let coordinator = AudioSessionCoordinator(engine: engine)
        try await coordinator.startRecording()
        try await coordinator.startRecording() // should not throw
        #expect(coordinator.state == .recording)
    }

    @Test("stopRecording when idle is ignored")
    func stopWhenIdle() async {
        let engine = MockAudioEngine()
        let coordinator = AudioSessionCoordinator(engine: engine)
        await coordinator.stopRecording() // should not throw
        #expect(coordinator.state == .idle)
        #expect(!engine.stopCalled)
    }

    @Test("engine failure on start throws and stays idle")
    func startFailure() async {
        let engine = MockAudioEngine()
        engine.shouldThrowOnStart = true
        let coordinator = AudioSessionCoordinator(engine: engine)
        do {
            try await coordinator.startRecording()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(coordinator.state == .idle)
        }
    }
}
