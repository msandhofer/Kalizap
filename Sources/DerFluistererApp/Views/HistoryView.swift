import SwiftUI
import DerFluisterer

struct HistoryView: View {
    @Bindable var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            if viewModel.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .task {
            await viewModel.loadEntries()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Suchen…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: viewModel.searchQuery.isEmpty ? "text.bubble" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.searchQuery.isEmpty
                 ? "Noch keine Diktate"
                 : "Keine Treffer für \u{201E}\(viewModel.searchQuery)\u{201C}")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(viewModel.entries) { entry in
                HistoryEntryRow(
                    entry: entry,
                    isCopied: viewModel.copiedEntryID == entry.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.copyToClipboard(entry)
                }
            }
            .onDelete { indexSet in
                let idsToDelete = indexSet.map { viewModel.entries[$0].id }
                Task {
                    for id in idsToDelete {
                        await viewModel.deleteEntry(id: id)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - Entry Row

struct HistoryEntryRow: View {
    let entry: DictationEntry
    let isCopied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.timestamp, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let app = entry.targetApp {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ZStack(alignment: .leading) {
                Text(entry.correctedText)
                    .lineLimit(2)
                    .font(.body)

                if isCopied {
                    Text("Kopiert!")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: isCopied)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
