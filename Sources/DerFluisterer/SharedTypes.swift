import Foundation

enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case de, en
}

enum ContextMode: String, Codable, CaseIterable, Sendable {
    case formal, informal, neutral, auto
}

struct CorrectionIntensity: Codable, Equatable, Sendable {
    var allowRephrasing: Bool = false
    var allowShortening: Bool = false
    var allowRestructuring: Bool = false
}

enum PipelineState: Equatable, Sendable {
    case idle
    case recording
    case processing(stage: ProcessingStage)
    case pendingInClipboard
    case error(PipelineError)

    enum ProcessingStage: String, Sendable {
        case transcribing, correcting, inserting
    }
}

struct PipelineError: Equatable, Sendable {
    let message: String
    let isRecoverable: Bool
}
