import Testing
import Foundation
import SwiftData
@testable import Kalizap

@Suite("HistoryViewModel")
struct HistoryViewModelTests {

    // MARK: - Helpers

    private func makeStore() throws -> DictationStoreImpl {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationRecord.self, configurations: config)
        return DictationStoreImpl(modelContainer: container)
    }

    private func makeEntry(
        correctedText: String = "Test",
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
            durationMs: 5000,
            processingTimeMs: 300
        )
    }

    // MARK: - Real-time Update

    @Test("entries update automatically after store save")
    @MainActor
    func entriesUpdateAfterSave() async throws {
        let store = try makeStore()
        let vm = HistoryViewModel(store: store)
        await vm.startObserving()

        #expect(vm.entries.isEmpty)

        try await store.save(makeEntry(correctedText: "Neuer Eintrag"))
        let arrived = await waitUntil { await MainActor.run { vm.entries.count == 1 } }
        #expect(arrived)

        #expect(vm.entries.count == 1)
        #expect(vm.entries[0].correctedText == "Neuer Eintrag")

        vm.stopObserving()
    }
}
