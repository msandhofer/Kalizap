import Foundation

public struct TranscriptionConfig: Sendable {
    public var language: SupportedLanguage = .de
    public var initialPrompt: String = ""

    public init(language: SupportedLanguage = .de, initialPrompt: String = "") {
        self.language = language
        self.initialPrompt = initialPrompt
    }
}

public struct PartialTranscription: Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public struct FinalTranscription: Sendable, Equatable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let processingTime: Duration

    public init(text: String, segments: [TranscriptionSegment], processingTime: Duration) {
        self.text = text
        self.segments = segments
        self.processingTime = processingTime
    }
}

public struct TranscriptionSegment: Sendable, Equatable {
    public let text: String
    public let range: Range<Duration>
    public let confidence: Float

    public init(text: String, range: Range<Duration>, confidence: Float) {
        self.text = text
        self.range = range
        self.confidence = confidence
    }
}

public enum TranscriptionResult: Sendable {
    case partial(PartialTranscription)
    case final(FinalTranscription)

    public var text: String {
        switch self {
        case .final(let ft): ft.text
        case .partial(let pt): pt.text
        }
    }
}

public enum TranscriptionLanguage: String, Sendable {
    case german = "de"
    case english = "en"
}

public enum TranscriptionError: Error, Sendable, Equatable, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(reason: String)
    case streamingFailed(reason: String)
    case batchFailed(reason: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "Whisper-Modell nicht geladen"
        case .modelLoadFailed(let reason): "Modell-Laden fehlgeschlagen: \(reason)"
        case .streamingFailed(let reason): "Streaming fehlgeschlagen: \(reason)"
        case .batchFailed(let reason): "Transkription fehlgeschlagen: \(reason)"
        case .cancelled: "Abgebrochen"
        }
    }
}

public protocol TranscriptionEngine: Sendable {
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
