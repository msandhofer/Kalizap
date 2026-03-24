import Foundation

public struct CorrectionConfig: Sendable {
    public var contextMode: ContextMode = .neutral
    public var intensity: CorrectionIntensity = .init()
    public var personalDictionary: [String] = []
    public var timeoutMs: Int = 800
    public var maxRetries: Int = 1

    public init(
        contextMode: ContextMode = .neutral,
        intensity: CorrectionIntensity = .init(),
        personalDictionary: [String] = [],
        timeoutMs: Int = 800,
        maxRetries: Int = 1
    ) {
        self.contextMode = contextMode
        self.intensity = intensity
        self.personalDictionary = personalDictionary
        self.timeoutMs = timeoutMs
        self.maxRetries = maxRetries
    }
}

public struct CorrectionStats: Sendable {
    public let latencyMs: Int
    public let tokensUsed: Int
    public let wasRetry: Bool

    public init(latencyMs: Int, tokensUsed: Int, wasRetry: Bool) {
        self.latencyMs = latencyMs
        self.tokensUsed = tokensUsed
        self.wasRetry = wasRetry
    }
}

public enum FallbackReason: Sendable {
    case apiError(underlying: Error)
    case timeout
    case retryExhausted
    case emptyResponse
}

public enum CorrectionOutcome: Sendable {
    case corrected(text: String, stats: CorrectionStats)
    case fallbackRaw(text: String, reason: FallbackReason)
}

public struct DebugSnapshot: Sendable {
    public let request: String
    public let response: String?
    public let outcome: CorrectionOutcome
    public let timestamp: Date

    public init(request: String, response: String?, outcome: CorrectionOutcome, timestamp: Date) {
        self.request = request
        self.response = response
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

public protocol TextCorrecting: Sendable {
    func correct(_ input: TranscriptionResult) async -> CorrectionOutcome
    func updateConfig(_ config: CorrectionConfig)
    var lastDebugSnapshot: DebugSnapshot? { get }
}
