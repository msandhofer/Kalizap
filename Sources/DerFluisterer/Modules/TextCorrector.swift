import Foundation

struct CorrectionConfig: Sendable {
    var contextMode: ContextMode = .neutral
    var intensity: CorrectionIntensity = .init()
    var personalDictionary: [String] = []
    var timeoutMs: Int = 800
    var maxRetries: Int = 1
}

struct CorrectionStats: Sendable {
    let latencyMs: Int
    let tokensUsed: Int
    let wasRetry: Bool
}

enum FallbackReason: Sendable {
    case apiError(underlying: Error)
    case timeout
    case retryExhausted
    case emptyResponse
}

enum CorrectionOutcome: Sendable {
    case corrected(text: String, stats: CorrectionStats)
    case fallbackRaw(text: String, reason: FallbackReason)
}

struct DebugSnapshot: Sendable {
    let request: String
    let response: String?
    let outcome: CorrectionOutcome
    let timestamp: Date
}

protocol TextCorrecting: Sendable {
    func correct(_ input: TranscriptionResult) async -> CorrectionOutcome
    func updateConfig(_ config: CorrectionConfig)
    var lastDebugSnapshot: DebugSnapshot? { get }
}
