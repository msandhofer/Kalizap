import Foundation

struct TranscriptionConfig: Sendable {
    var language: SupportedLanguage = .de
    var initialPrompt: String = ""
}

struct PartialTranscription: Sendable {
    let text: String
    let confidence: Float
}

struct FinalTranscription: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let processingTime: Duration
}

struct TranscriptionSegment: Sendable {
    let text: String
    let range: Range<Duration>
    let confidence: Float
}

enum TranscriptionResult: Sendable {
    case partial(PartialTranscription)
    case final(FinalTranscription)
}

enum TranscriptionLanguage: String, Sendable {
    case german = "de"
    case english = "en"
}

enum TranscriptionError: Error, Sendable {
    case modelNotLoaded
    case modelLoadFailed(underlying: Error)
    case streamingFailed(reason: String)
    case batchFailed(reason: String)
    case cancelled
}

protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult>

    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws

    func cancel()
}
