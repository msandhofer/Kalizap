import Foundation

@Observable @MainActor
public final class StatisticsViewModel {
    public private(set) var statistics = DictationStatistics(
        totalCount: 0, todayCount: 0, weekCount: 0,
        totalWords: 0, averageWPM: 0, currentStreakDays: 0,
        averageProcessingTimeMs: 0
    )

    private let store: any DictationStoring
    private var observeTask: Task<Void, Never>?

    public init(store: any DictationStoring) {
        self.store = store
    }

    public func load() async {
        statistics = await store.statistics()
    }

    public func startObserving() async {
        await load()
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.store.didChange {
                if Task.isCancelled { break }
                await self.load()
            }
        }
    }

    public func stopObserving() {
        observeTask?.cancel()
        observeTask = nil
    }
}
