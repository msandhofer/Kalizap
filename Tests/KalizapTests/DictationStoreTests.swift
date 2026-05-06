import Testing
import Foundation
import SwiftData
@testable import Kalizap

@Suite("DictationStore")
struct DictationStoreTests {

    // MARK: - Helpers

    private func makeSUT() throws -> DictationStoreImpl {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationRecord.self, configurations: config)
        return DictationStoreImpl(modelContainer: container)
    }

    private func makeEntry(
        rawTranscript: String = "rohes transkript",
        correctedText: String = "Korrigierter Text",
        language: String = "de",
        contextMode: String = "neutral",
        targetApp: String? = "TestApp",
        durationMs: Int = 5000,
        processingTimeMs: Int = 350,
        timestamp: Date = Date()
    ) -> DictationEntry {
        DictationEntry(
            id: UUID(),
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

    // MARK: - Tracer Bullet: Save + Fetch

    @Test("saved record is retrievable via fetchAll with correct fields")
    func saveAndFetch() async throws {
        let store = try makeSUT()
        let entry = makeEntry(
            rawTranscript: "hallo welt",
            correctedText: "Hallo Welt",
            language: "de",
            contextMode: "formal",
            targetApp: "Notes",
            durationMs: 3000,
            processingTimeMs: 250
        )

        try await store.save(entry)
        let fetched = try await store.fetchAll()

        #expect(fetched.count == 1)
        #expect(fetched[0].rawTranscript == "hallo welt")
        #expect(fetched[0].correctedText == "Hallo Welt")
        #expect(fetched[0].language == "de")
        #expect(fetched[0].contextMode == "formal")
        #expect(fetched[0].targetApp == "Notes")
        #expect(fetched[0].durationMs == 3000)
        #expect(fetched[0].processingTimeMs == 250)
    }

    // MARK: - Chronological Sort

    @Test("fetchAll returns entries sorted newest first")
    func fetchAllSortedNewestFirst() async throws {
        let store = try makeSUT()
        let old = makeEntry(correctedText: "Alt", timestamp: Date(timeIntervalSince1970: 1000))
        let mid = makeEntry(correctedText: "Mitte", timestamp: Date(timeIntervalSince1970: 2000))
        let new_ = makeEntry(correctedText: "Neu", timestamp: Date(timeIntervalSince1970: 3000))

        // Save in random order
        try await store.save(mid)
        try await store.save(old)
        try await store.save(new_)

        let fetched = try await store.fetchAll()

        #expect(fetched.count == 3)
        #expect(fetched[0].correctedText == "Neu")
        #expect(fetched[1].correctedText == "Mitte")
        #expect(fetched[2].correctedText == "Alt")
    }

    // MARK: - Delete

    @Test("deleted entry is no longer in fetchAll")
    func deleteRemovesEntry() async throws {
        let store = try makeSUT()
        let entry1 = makeEntry(correctedText: "Erster")
        let entry2 = makeEntry(correctedText: "Zweiter")

        try await store.save(entry1)
        try await store.save(entry2)
        try await store.delete(id: entry1.id)

        let fetched = try await store.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].correctedText == "Zweiter")
    }

    // MARK: - Search

    @Test("search finds matches in rawTranscript and correctedText case-insensitively")
    func searchFindsInBothFields() async throws {
        let store = try makeSUT()
        let entry1 = makeEntry(rawTranscript: "hallo welt", correctedText: "Hallo Welt")
        let entry2 = makeEntry(rawTranscript: "guten morgen", correctedText: "Guten Morgen")
        let entry3 = makeEntry(rawTranscript: "tschüss", correctedText: "Auf Wiedersehen")

        try await store.save(entry1)
        try await store.save(entry2)
        try await store.save(entry3)

        // Match in correctedText
        let results1 = try await store.search(query: "hallo")
        #expect(results1.count == 1)
        #expect(results1[0].correctedText == "Hallo Welt")

        // Match in rawTranscript
        let results2 = try await store.search(query: "guten")
        #expect(results2.count == 1)
        #expect(results2[0].correctedText == "Guten Morgen")

        // Case-insensitive: "WELT" matches "Welt"
        let results3 = try await store.search(query: "WELT")
        #expect(results3.count == 1)
    }

    @Test("search returns empty array when no match")
    func searchNoMatch() async throws {
        let store = try makeSUT()
        try await store.save(makeEntry(rawTranscript: "hallo", correctedText: "Hallo"))

        let results = try await store.search(query: "xyz")
        #expect(results.isEmpty)
    }

    // MARK: - History Limit

    @Test("saving beyond history limit removes oldest entry")
    func historyLimitEnforced() async throws {
        let store = try makeSUT()
        try await store.updateHistoryLimit(3)

        let e1 = makeEntry(correctedText: "Eins", timestamp: Date(timeIntervalSince1970: 1000))
        let e2 = makeEntry(correctedText: "Zwei", timestamp: Date(timeIntervalSince1970: 2000))
        let e3 = makeEntry(correctedText: "Drei", timestamp: Date(timeIntervalSince1970: 3000))
        let e4 = makeEntry(correctedText: "Vier", timestamp: Date(timeIntervalSince1970: 4000))

        try await store.save(e1)
        try await store.save(e2)
        try await store.save(e3)
        try await store.save(e4)

        let fetched = try await store.fetchAll()
        #expect(fetched.count == 3)
        #expect(fetched[0].correctedText == "Vier")
        #expect(fetched[1].correctedText == "Drei")
        #expect(fetched[2].correctedText == "Zwei")
    }

    @Test("updateHistoryLimit trims excess entries immediately")
    func updateHistoryLimitTrims() async throws {
        let store = try makeSUT()
        let e1 = makeEntry(correctedText: "Eins", timestamp: Date(timeIntervalSince1970: 1000))
        let e2 = makeEntry(correctedText: "Zwei", timestamp: Date(timeIntervalSince1970: 2000))
        let e3 = makeEntry(correctedText: "Drei", timestamp: Date(timeIntervalSince1970: 3000))

        try await store.save(e1)
        try await store.save(e2)
        try await store.save(e3)

        try await store.updateHistoryLimit(1)

        let fetched = try await store.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].correctedText == "Drei")
    }

    // MARK: - Statistics

    @Test("statistics counts: totalCount, todayCount, weekCount")
    func statisticsCounts() async throws {
        let store = try makeSUT()
        let now = Date()
        let today = makeEntry(correctedText: "Heute", timestamp: now)
        let yesterday = makeEntry(
            correctedText: "Gestern",
            timestamp: Calendar.current.date(byAdding: .day, value: -1, to: now)!
        )
        let lastMonth = makeEntry(
            correctedText: "Letzter Monat",
            timestamp: Calendar.current.date(byAdding: .day, value: -35, to: now)!
        )

        try await store.save(today)
        try await store.save(yesterday)
        try await store.save(lastMonth)

        let stats = await store.statistics()
        #expect(stats.totalCount == 3)
        #expect(stats.todayCount == 1)
        #expect(stats.weekCount == 2)
    }

    @Test("statistics: totalWords and averageWPM")
    func statisticsWordsAndWPM() async throws {
        let store = try makeSUT()
        // "Hallo Welt" = 2 words, 6000ms = 0.1min → WPM = 2/0.1 = 20
        let e1 = makeEntry(correctedText: "Hallo Welt", durationMs: 6000)
        // "Eins Zwei Drei Vier" = 4 words, 3000ms = 0.05min → WPM = 4/0.05 = 80
        let e2 = makeEntry(correctedText: "Eins Zwei Drei Vier", durationMs: 3000)

        try await store.save(e1)
        try await store.save(e2)

        let stats = await store.statistics()
        #expect(stats.totalWords == 6)
        #expect(stats.averageWPM == 50.0) // (20 + 80) / 2
    }

    @Test("statistics: streak counts consecutive days with dictations")
    func statisticsStreak() async throws {
        let store = try makeSUT()
        let now = Date()
        let calendar = Calendar.current

        // Today, yesterday, day before = 3-day streak
        let today = makeEntry(timestamp: now)
        let yesterday = makeEntry(timestamp: calendar.date(byAdding: .day, value: -1, to: now)!)
        let dayBefore = makeEntry(timestamp: calendar.date(byAdding: .day, value: -2, to: now)!)
        // Gap: skip day -3
        let fourDaysAgo = makeEntry(timestamp: calendar.date(byAdding: .day, value: -4, to: now)!)

        try await store.save(today)
        try await store.save(yesterday)
        try await store.save(dayBefore)
        try await store.save(fourDaysAgo)

        let stats = await store.statistics()
        #expect(stats.currentStreakDays == 3)
    }

    @Test("statistics: averageProcessingTimeMs")
    func statisticsProcessingTime() async throws {
        let store = try makeSUT()
        try await store.save(makeEntry(processingTimeMs: 200))
        try await store.save(makeEntry(processingTimeMs: 400))

        let stats = await store.statistics()
        #expect(stats.averageProcessingTimeMs == 300.0)
    }

    // MARK: - Empty State

    @Test("all methods work correctly on empty store")
    func emptyStore() async throws {
        let store = try makeSUT()

        let fetched = try await store.fetchAll()
        #expect(fetched.isEmpty)

        let results = try await store.search(query: "anything")
        #expect(results.isEmpty)

        let stats = await store.statistics()
        #expect(stats.totalCount == 0)
        #expect(stats.todayCount == 0)
        #expect(stats.weekCount == 0)
        #expect(stats.totalWords == 0)
        #expect(stats.averageWPM == 0)
        #expect(stats.currentStreakDays == 0)
        #expect(stats.averageProcessingTimeMs == 0)
    }
}
