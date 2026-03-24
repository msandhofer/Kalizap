import Foundation

public struct DictationStatistics: Sendable, Equatable {
    public let totalCount: Int
    public let todayCount: Int
    public let weekCount: Int
    public let totalWords: Int
    public let averageWPM: Double
    public let currentStreakDays: Int
    public let averageProcessingTimeMs: Double

    public init(
        totalCount: Int, todayCount: Int, weekCount: Int,
        totalWords: Int, averageWPM: Double, currentStreakDays: Int,
        averageProcessingTimeMs: Double
    ) {
        self.totalCount = totalCount
        self.todayCount = todayCount
        self.weekCount = weekCount
        self.totalWords = totalWords
        self.averageWPM = averageWPM
        self.currentStreakDays = currentStreakDays
        self.averageProcessingTimeMs = averageProcessingTimeMs
    }
}

public protocol DictationStoring: Sendable {
    func save(_ entry: DictationEntry) async throws
    func delete(id: UUID) async throws
    func fetchAll() async throws -> [DictationEntry]
    func search(query: String) async throws -> [DictationEntry]
    func statistics() async -> DictationStatistics
    func updateHistoryLimit(_ limit: Int) async throws
    var didChange: AsyncStream<Void> { get }
}
