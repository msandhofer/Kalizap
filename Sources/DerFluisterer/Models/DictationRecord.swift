import Foundation
import SwiftData

public struct DictationEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let rawTranscript: String
    public let correctedText: String
    public let language: String
    public let contextMode: String
    public let targetApp: String?
    public let durationMs: Int
    public let processingTimeMs: Int

    public var wordCount: Int {
        correctedText.split(separator: " ").count
    }

    public var wordsPerMinute: Double {
        guard durationMs > 0 else { return 0 }
        return Double(wordCount) / (Double(durationMs) / 60_000)
    }

    public init(
        id: UUID,
        timestamp: Date,
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

@Model
public final class DictationRecord {
    @Attribute(.unique) public var id: UUID
    var timestamp: Date
    var rawTranscript: String
    var correctedText: String
    var language: String
    var contextMode: String
    var targetApp: String?
    var durationMs: Int
    var processingTimeMs: Int

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

    var asEntry: DictationEntry {
        DictationEntry(
            id: id,
            timestamp: timestamp,
            rawTranscript: rawTranscript,
            correctedText: correctedText,
            language: language,
            contextMode: contextMode,
            targetApp: targetApp,
            durationMs: durationMs,
            processingTimeMs: processingTimeMs
        )
    }
}
