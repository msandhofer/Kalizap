import Foundation

public struct WhisperTranscriptionResult: Sendable {
    public let text: String
    public let segments: [TranscriptionSegment]

    public init(text: String, segments: [TranscriptionSegment]) {
        self.text = text
        self.segments = segments
    }
}

public protocol WhisperBackend: Sendable {
    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws

    func transcribe(
        samples: [Float],
        language: String,
        prompt: String
    ) async throws -> WhisperTranscriptionResult
}

public final class BatchTranscriber: @unchecked Sendable {
    private let backend: WhisperBackend
    private var modelLoaded = false

    public init(backend: WhisperBackend) {
        self.backend = backend
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        try await backend.loadModel(for: language, onProgress: onProgress)
        modelLoaded = true
    }

    public func transcribe(
        buffer: CollectedAudioBuffer,
        config: TranscriptionConfig
    ) async throws -> FinalTranscription {
        guard modelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        let start = ContinuousClock.now

        let result = try await backend.transcribe(
            samples: buffer.samples,
            language: config.language.rawValue,
            prompt: config.initialPrompt
        )

        let elapsed = ContinuousClock.now - start

        return FinalTranscription(
            text: result.text,
            segments: result.segments,
            processingTime: elapsed
        )
    }
}
