import Foundation
import SwiftData

public final class ChangeNotifier: Sendable {
    public let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    public init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func notify() {
        continuation.yield()
    }
}

public actor DictationStoreImpl: DictationStoring {

    private static let newestFirst = [SortDescriptor(\DictationRecord.timestamp, order: .reverse)]
    private var historyLimit: Int = 100
    private let changeNotifier: ChangeNotifier
    private let modelContext: ModelContext

    public nonisolated var didChange: AsyncStream<Void> { changeNotifier.stream }

    public init(modelContainer: ModelContainer, changeNotifier: ChangeNotifier = ChangeNotifier()) {
        self.changeNotifier = changeNotifier
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelContext = context
    }

    public func save(_ entry: DictationEntry) throws {
        let record = DictationRecord(
            id: entry.id,
            timestamp: entry.timestamp,
            rawTranscript: entry.rawTranscript,
            correctedText: entry.correctedText,
            language: entry.language,
            contextMode: entry.contextMode,
            targetApp: entry.targetApp,
            durationMs: entry.durationMs,
            processingTimeMs: entry.processingTimeMs,
            normalizationMs: entry.normalizationMs,
            transcriptionMs: entry.transcriptionMs,
            correctionMs: entry.correctionMs,
            insertionMs: entry.insertionMs,
            usedStreamingResult: entry.usedStreamingResult,
            audioSampleCount: entry.audioSampleCount,
            stopSoundMs: entry.stopSoundMs,
            recorderStopMs: entry.recorderStopMs,
            streamingWaitMs: entry.streamingWaitMs
        )
        modelContext.insert(record)
        try modelContext.save()
        try trimToLimit()
        changeNotifier.notify()
    }

    public func delete(id: UUID) throws {
        let predicate = #Predicate<DictationRecord> { $0.id == id }
        let descriptor = FetchDescriptor<DictationRecord>(predicate: predicate)
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
            changeNotifier.notify()
        }
    }

    public func fetchAll() throws -> [DictationEntry] {
        var descriptor = FetchDescriptor<DictationRecord>()
        descriptor.sortBy = Self.newestFirst
        return try modelContext.fetch(descriptor).map { $0.asEntry }
    }

    public func search(query: String) throws -> [DictationEntry] {
        let lowered = query.lowercased()
        let predicate = #Predicate<DictationRecord> {
            $0.rawTranscript.localizedStandardContains(lowered) ||
            $0.correctedText.localizedStandardContains(lowered)
        }
        var descriptor = FetchDescriptor<DictationRecord>(predicate: predicate)
        descriptor.sortBy = Self.newestFirst
        return try modelContext.fetch(descriptor).map { $0.asEntry }
    }

    public func statistics() -> DictationStatistics {
        let all: [DictationRecord]
        do {
            all = try modelContext.fetch(FetchDescriptor<DictationRecord>())
        } catch {
            return DictationStatistics(
                totalCount: 0, todayCount: 0, weekCount: 0,
                totalWords: 0, averageWPM: 0, currentStreakDays: 0,
                averageProcessingTimeMs: 0
            )
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: now)!

        let todayCount = all.filter { $0.timestamp >= startOfToday }.count
        let weekCount = all.filter { $0.timestamp >= startOfWeek }.count

        return DictationStatistics(
            totalCount: all.count,
            todayCount: todayCount,
            weekCount: weekCount,
            totalWords: all.reduce(0) { $0 + $1.asEntry.wordCount },
            averageWPM: all.isEmpty ? 0 : all.reduce(0.0) { $0 + $1.asEntry.wordsPerMinute } / Double(all.count),
            currentStreakDays: computeStreak(from: all),
            averageProcessingTimeMs: all.isEmpty ? 0 : Double(all.reduce(0) { $0 + $1.processingTimeMs }) / Double(all.count)
        )
    }

    public func updateHistoryLimit(_ limit: Int) throws {
        historyLimit = limit
        try trimToLimit()
    }

    private func computeStreak(from records: [DictationRecord]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.timestamp) })
            .sorted(by: >)

        var streak = 0
        var expectedDay = today
        for day in uniqueDays {
            if day == expectedDay {
                streak += 1
                expectedDay = calendar.date(byAdding: .day, value: -1, to: expectedDay)!
            } else {
                break
            }
        }
        return streak
    }

    private func trimToLimit() throws {
        var descriptor = FetchDescriptor<DictationRecord>()
        descriptor.sortBy = Self.newestFirst
        let all = try modelContext.fetch(descriptor)
        if all.count > historyLimit {
            for record in all[historyLimit...] {
                modelContext.delete(record)
            }
            try modelContext.save()
        }
    }
}
