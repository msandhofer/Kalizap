import Testing
import Foundation
@testable import DerFluisterer

// MARK: - Mock Whisper Backend

final class MockWhisperBackend: WhisperBackend, @unchecked Sendable {
    var loadedLanguage: TranscriptionLanguage?
    var lastSamples: [Float]?
    var lastLanguage: String?
    var lastPrompt: String?
    var resultText: String = "Hallo Welt"
    var shouldThrow = false

    func loadModel(for language: TranscriptionLanguage, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        loadedLanguage = language
        onProgress(0.5)
        onProgress(1.0)
    }

    func transcribe(samples: [Float], language: String, prompt: String) async throws -> WhisperTranscriptionResult {
        if shouldThrow {
            throw TranscriptionError.batchFailed(reason: "mock error")
        }
        lastSamples = samples
        lastLanguage = language
        lastPrompt = prompt
        return WhisperTranscriptionResult(text: resultText, segments: [])
    }

    func detectSilenceBoundaries(samples: [Float]) -> [Float] { [] }
}

// MARK: - Tests

@Suite("BatchTranscriber")
struct BatchTranscriberTests {

    @Test("transcribes audio buffer with correct language")
    func transcribesWithLanguage() async throws {
        let backend = MockWhisperBackend()
        let transcriber = BatchTranscriber(backend: backend)
        try await transcriber.loadModel(for: .german) { _ in }

        let buffer = CollectedAudioBuffer(samples: [0.1, 0.2], sampleRate: 16000, totalDuration: 1.0)
        let config = TranscriptionConfig(language: .de, initialPrompt: "")

        let result = try await transcriber.transcribe(buffer: buffer, config: config)
        #expect(result.text == "Hallo Welt")
        #expect(backend.lastLanguage == "de")
    }

    @Test("passes initial prompt to backend")
    func passesPrompt() async throws {
        let backend = MockWhisperBackend()
        let transcriber = BatchTranscriber(backend: backend)
        try await transcriber.loadModel(for: .german) { _ in }

        let buffer = CollectedAudioBuffer(samples: [0.1], sampleRate: 16000, totalDuration: 0.5)
        let config = TranscriptionConfig(language: .de, initialPrompt: "Kubernetes, PostgreSQL")

        _ = try await transcriber.transcribe(buffer: buffer, config: config)
        #expect(backend.lastPrompt == "Kubernetes, PostgreSQL")
    }

    @Test("throws when model not loaded")
    func modelNotLoaded() async {
        let backend = MockWhisperBackend()
        let transcriber = BatchTranscriber(backend: backend)

        let buffer = CollectedAudioBuffer(samples: [0.1], sampleRate: 16000, totalDuration: 0.5)
        let config = TranscriptionConfig()

        do {
            _ = try await transcriber.transcribe(buffer: buffer, config: config)
            Issue.record("Expected error")
        } catch let error as TranscriptionError {
            #expect(error == .modelNotLoaded)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("backend error is propagated")
    func backendError() async throws {
        let backend = MockWhisperBackend()
        backend.shouldThrow = true
        let transcriber = BatchTranscriber(backend: backend)
        try await transcriber.loadModel(for: .german) { _ in }

        let buffer = CollectedAudioBuffer(samples: [0.1], sampleRate: 16000, totalDuration: 0.5)
        let config = TranscriptionConfig()

        do {
            _ = try await transcriber.transcribe(buffer: buffer, config: config)
            Issue.record("Expected error")
        } catch {
            // Error propagated correctly
        }
    }

    @Test("measures processing time")
    func processingTime() async throws {
        let backend = MockWhisperBackend()
        let transcriber = BatchTranscriber(backend: backend)
        try await transcriber.loadModel(for: .german) { _ in }

        let buffer = CollectedAudioBuffer(samples: [0.1], sampleRate: 16000, totalDuration: 0.5)
        let result = try await transcriber.transcribe(buffer: buffer, config: TranscriptionConfig())
        #expect(result.processingTime >= .zero)
    }
}
