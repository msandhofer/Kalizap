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

    // Per-stage timing (optional for backward compatibility with old records)
    public let normalizationMs: Int?
    public let transcriptionMs: Int?
    public let correctionMs: Int?
    public let insertionMs: Int?
    public let usedStreamingResult: Bool?
    public let audioSampleCount: Int?
    public let whisperModel: String?
    public let whisperEngine: String?

    // Overhead timing (time between user stop and processing start)
    public let stopSoundMs: Int?
    public let recorderStopMs: Int?
    public let streamingWaitMs: Int?

    public var wordCount: Int {
        correctedText.split(separator: " ").count
    }

    public var wordsPerMinute: Double {
        guard durationMs > 0 else { return 0 }
        return Double(wordCount) / (Double(durationMs) / 60_000)
    }

    public var overheadMs: Int? {
        guard let norm = normalizationMs, let trans = transcriptionMs,
              let corr = correctionMs, let ins = insertionMs else { return nil }
        return max(0, processingTimeMs - (norm + trans + corr + ins))
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
        processingTimeMs: Int,
        normalizationMs: Int? = nil,
        transcriptionMs: Int? = nil,
        correctionMs: Int? = nil,
        insertionMs: Int? = nil,
        usedStreamingResult: Bool? = nil,
        audioSampleCount: Int? = nil,
        whisperModel: String? = nil,
        whisperEngine: String? = nil,
        stopSoundMs: Int? = nil,
        recorderStopMs: Int? = nil,
        streamingWaitMs: Int? = nil
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
        self.normalizationMs = normalizationMs
        self.transcriptionMs = transcriptionMs
        self.correctionMs = correctionMs
        self.insertionMs = insertionMs
        self.usedStreamingResult = usedStreamingResult
        self.audioSampleCount = audioSampleCount
        self.whisperModel = whisperModel
        self.whisperEngine = whisperEngine
        self.stopSoundMs = stopSoundMs
        self.recorderStopMs = recorderStopMs
        self.streamingWaitMs = streamingWaitMs
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
    var normalizationMs: Int?
    var transcriptionMs: Int?
    var correctionMs: Int?
    var insertionMs: Int?
    var usedStreamingResult: Bool?
    var audioSampleCount: Int?
    var whisperModel: String?
    var whisperEngine: String?
    var stopSoundMs: Int?
    var recorderStopMs: Int?
    var streamingWaitMs: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawTranscript: String,
        correctedText: String,
        language: String,
        contextMode: String,
        targetApp: String?,
        durationMs: Int,
        processingTimeMs: Int,
        normalizationMs: Int? = nil,
        transcriptionMs: Int? = nil,
        correctionMs: Int? = nil,
        insertionMs: Int? = nil,
        usedStreamingResult: Bool? = nil,
        audioSampleCount: Int? = nil,
        whisperModel: String? = nil,
        whisperEngine: String? = nil,
        stopSoundMs: Int? = nil,
        recorderStopMs: Int? = nil,
        streamingWaitMs: Int? = nil
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
        self.normalizationMs = normalizationMs
        self.transcriptionMs = transcriptionMs
        self.correctionMs = correctionMs
        self.insertionMs = insertionMs
        self.usedStreamingResult = usedStreamingResult
        self.audioSampleCount = audioSampleCount
        self.whisperModel = whisperModel
        self.whisperEngine = whisperEngine
        self.stopSoundMs = stopSoundMs
        self.recorderStopMs = recorderStopMs
        self.streamingWaitMs = streamingWaitMs
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
            processingTimeMs: processingTimeMs,
            normalizationMs: normalizationMs,
            transcriptionMs: transcriptionMs,
            correctionMs: correctionMs,
            insertionMs: insertionMs,
            usedStreamingResult: usedStreamingResult,
            audioSampleCount: audioSampleCount,
            whisperModel: whisperModel,
            whisperEngine: whisperEngine,
            stopSoundMs: stopSoundMs,
            recorderStopMs: recorderStopMs,
            streamingWaitMs: streamingWaitMs
        )
    }
}
