import AppKit

@Observable @MainActor
public final class HistoryViewModel {
    public private(set) var entries: [DictationEntry] = []
    public var searchQuery: String = "" {
        didSet { Task { await performSearch() } }
    }
    public private(set) var copiedEntryID: UUID?

    private let store: any DictationStoring
    private var observeTask: Task<Void, Never>?

    public init(store: any DictationStoring) {
        self.store = store
    }

    public func loadEntries() async {
        do {
            entries = try await store.fetchAll()
        } catch {
            entries = []
        }
    }

    public func deleteEntry(id: UUID) async {
        do {
            try await store.delete(id: id)
            entries.removeAll { $0.id == id }
        } catch {}
    }

    public func copyToClipboard(_ entry: DictationEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.correctedText, forType: .string)

        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }

    public func startObserving() async {
        await loadEntries()
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.store.didChange {
                if Task.isCancelled { break }
                await self.loadEntries()
            }
        }
    }

    public func stopObserving() {
        observeTask?.cancel()
        observeTask = nil
    }

    private func performSearch() async {
        if searchQuery.isEmpty {
            await loadEntries()
        } else {
            do {
                entries = try await store.search(query: searchQuery)
            } catch {
                entries = []
            }
        }
    }
}
