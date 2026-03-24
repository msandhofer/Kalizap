import Foundation
import SwiftData

@Model
final class DictationRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawTranscript: String
    var correctedText: String
    var language: String
    var contextMode: String
    var targetApp: String?
    var durationMs: Int
    var processingTimeMs: Int

    var wordCount: Int {
        correctedText.split(separator: " ").count
    }

    var wordsPerMinute: Double {
        guard durationMs > 0 else { return 0 }
        return Double(wordCount) / (Double(durationMs) / 60_000)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawTranscript: String,
        correctedText: String,
        language: String,
        contextMode: String,
        targetApp: String?,
        durationMs: Int,
        processingTimeMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.correctedText = correctedText
        self.language = language
        self.contextMode = contextMode
        self.targetApp = targetApp
        self.durationMs = durationMs
        self.processingTimeMs = processingTimeMs
    }
}
