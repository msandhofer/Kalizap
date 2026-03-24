import Foundation

struct DictationStatistics: Sendable, Equatable {
    let totalCount: Int
    let todayCount: Int
    let weekCount: Int
    let totalWords: Int
    let averageWPM: Double
    let currentStreakDays: Int
    let averageProcessingTimeMs: Double
}

protocol DictationStoring: Sendable {
    func save(_ record: DictationRecord) throws
    func delete(_ record: DictationRecord) throws
    func statistics() -> DictationStatistics
    func updateHistoryLimit(_ limit: Int) throws
}
