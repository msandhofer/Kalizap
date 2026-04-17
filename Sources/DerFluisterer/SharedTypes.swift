import Foundation

public enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case de, en

    public var transcriptionLanguage: TranscriptionLanguage {
        switch self {
        case .de: .german
        case .en: .english
        }
    }
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

public struct CorrectionTasks: Codable, Equatable, Sendable {
    public var grammar: Bool = true
    public var fillerRemoval: Bool = true
    public var writtenLanguage: Bool = true
    public var punctuation: Bool = true
    public var preventHallucination: Bool = true

    public init(
        grammar: Bool = true,
        fillerRemoval: Bool = true,
        writtenLanguage: Bool = true,
        punctuation: Bool = true,
        preventHallucination: Bool = true
    ) {
        self.grammar = grammar
        self.fillerRemoval = fillerRemoval
        self.writtenLanguage = writtenLanguage
        self.punctuation = punctuation
        self.preventHallucination = preventHallucination
    }

    public var isEmpty: Bool {
        !grammar && !fillerRemoval && !writtenLanguage && !punctuation && !preventHallucination
    }
}

public enum PipelineState: Equatable, Sendable {
    case loadingModel(progress: Double)
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
