import Foundation

public struct DictationStatistics: Sendable, Equatable {
    let totalCount: Int
    let todayCount: Int
    let weekCount: Int
    let totalWords: Int
    let averageWPM: Double
    let currentStreakDays: Int
    let averageProcessingTimeMs: Double
}

public protocol DictationStoring: Sendable {
    func save(_ entry: DictationEntry) async throws
    func delete(id: UUID) async throws
    func fetchAll() async throws -> [DictationEntry]
    func search(query: String) async throws -> [DictationEntry]
    func statistics() async -> DictationStatistics
    func updateHistoryLimit(_ limit: Int) async throws
}
