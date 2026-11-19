import Testing
import Foundation
import SwiftData
@testable import Kalizap

@Suite("DictationContainerFactory", .serialized)
struct DictationContainerFactoryTests {

    private let dir: URL
    private var storeURL: URL { dir.appending(path: "Dictations.store") }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appending(path: "dcf-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeEntry(text: String = "Hallo Welt") -> DictationEntry {
        DictationEntry(
            id: UUID(), timestamp: Date(), rawTranscript: text, correctedText: text,
            language: "de", contextMode: "neutral", targetApp: nil,
            durationMs: 1000, processingTimeMs: 100
        )
    }

    @Test("records persist across container instances at the given store URL")
    func persistsAcrossRestart() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = DictationStoreImpl(modelContainer: DictationContainerFactory.makeContainer(storeURL: storeURL))
        try await first.save(makeEntry(text: "persistiert"))

        let second = DictationStoreImpl(modelContainer: DictationContainerFactory.makeContainer(storeURL: storeURL))
        let all = try await second.fetchAll()

        #expect(all.map(\.correctedText) == ["persistiert"])
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("foreign store at the URL is moved aside and a working store is created")
    func recoversFromForeignStore() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeForeignStore(at: storeURL)

        let store = DictationStoreImpl(modelContainer: DictationContainerFactory.makeContainer(storeURL: storeURL))
        try await store.save(makeEntry(text: "nach Recovery"))

        let reopened = DictationStoreImpl(modelContainer: DictationContainerFactory.makeContainer(storeURL: storeURL))
        #expect(try await reopened.fetchAll().map(\.correctedText) == ["nach Recovery"])

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("Dictations.store.broken-") })
    }

    @Test("unusable store location falls back to a working in-memory store")
    func fallsBackToInMemory() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        // Parent "directory" is a regular file → store can never be created there.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let blocker = dir.appending(path: "blocker")
        try Data("x".utf8).write(to: blocker)

        let store = DictationStoreImpl(modelContainer: DictationContainerFactory.makeContainer(
            storeURL: blocker.appending(path: "Dictations.store")
        ))
        try await store.save(makeEntry(text: "nur im Speicher"))

        #expect(try await store.fetchAll().map(\.correctedText) == ["nur im Speicher"])
    }

    /// Simulates another process (e.g. icloudmailagent) owning a SwiftData store with an unrelated schema.
    private func writeForeignStore(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try ModelContainer(
            for: ForeignRequestModel.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        context.insert(ForeignRequestModel(uuid: "x"))
        try context.save()
    }
}

@Model
final class ForeignRequestModel {
    var uuid: String
    init(uuid: String) { self.uuid = uuid }
}
