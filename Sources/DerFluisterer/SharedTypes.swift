import Foundation

public enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case de, en
}

public enum ContextMode: String, Codable, CaseIterable, Sendable {
    case formal, informal, neutral, auto
}

public struct CorrectionIntensity: Codable, Equatable, Sendable {
    public var allowRephrasing: Bool = false
    public var allowShortening: Bool = false
    public var allowRestructuring: Bool = false
    public init(allowRephrasing: Bool = false, allowShortening: Bool = false, allowRestructuring: Bool = false) {
        self.allowRephrasing = allowRephrasing
        self.allowShortening = allowShortening
        self.allowRestructuring = allowRestructuring
    }
}

public enum PipelineState: Equatable, Sendable {
    case idle
    case recording
    case processing(stage: ProcessingStage)
    case pendingInClipboard
    case error(PipelineError)

    public enum ProcessingStage: String, Sendable {
        case transcribing, correcting, inserting
    }
}

public struct PipelineError: Equatable, Sendable {
    public let message: String
    public let isRecoverable: Bool
    public init(message: String, isRecoverable: Bool) {
        self.message = message
        self.isRecoverable = isRecoverable
    }
}
