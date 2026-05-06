import Testing
import Foundation
import SwiftData
@testable import Kalizap

@Suite("StatisticsViewModel")
struct StatisticsViewModelTests {

    // MARK: - Helpers

    private func makeStore() throws -> DictationStoreImpl {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationRecord.self, configurations: config)
        return DictationStoreImpl(modelContainer: container)
    }

    private func makeEntry(
        correctedText: String = "Test",
        durationMs: Int = 5000,
        processingTimeMs: Int = 300,
        timestamp: Date = Date()
    ) -> DictationEntry {
        DictationEntry(
            id: UUID(),
            timestamp: timestamp,
            rawTranscript: "test",
            correctedText: correctedText,
            language: "de",
            contextMode: "neutral",
            targetApp: "TestApp",
            durationMs: durationMs,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Tracer Bullet

    @Test("load fetches statistics from store")
    @MainActor
    func loadFetchesStatistics() async throws {
        let store = try makeStore()
        try await store.save(makeEntry(correctedText: "Hallo Welt"))
        try await store.save(makeEntry(correctedText: "Noch ein Test"))

        let vm = StatisticsViewModel(store: store)
        await vm.load()

        #expect(vm.statistics.totalCount == 2)
    }

    // MARK: - Real-time Update

    @Test("statistics update automatically after store save")
    @MainActor
    func statisticsUpdateAfterSave() async throws {
        let store = try makeStore()
        let vm = StatisticsViewModel(store: store)
        await vm.startObserving()

        #expect(vm.statistics.totalCount == 0)

        try await store.save(makeEntry())
        try? await Task.sleep(for: .milliseconds(100))

        #expect(vm.statistics.totalCount == 1)

        vm.stopObserving()
    }
}
