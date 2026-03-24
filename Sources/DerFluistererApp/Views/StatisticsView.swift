import SwiftUI
import DerFluisterer

struct StatisticsView: View {
    @Bindable var viewModel: StatisticsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                countSection
                performanceSection
                streakSection
            }
            .padding()
        }
        .task {
            await viewModel.startObserving()
        }
    }

    // MARK: - Counts

    private var countSection: some View {
        GroupBox("Diktate") {
            HStack(spacing: 24) {
                StatCard(title: "Gesamt", value: "\(viewModel.statistics.totalCount)")
                Divider().frame(height: 40)
                StatCard(title: "Heute", value: "\(viewModel.statistics.todayCount)")
                Divider().frame(height: 40)
                StatCard(title: "Diese Woche", value: "\(viewModel.statistics.weekCount)")
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        GroupBox("Leistung") {
            HStack(spacing: 24) {
                StatCard(
                    title: "Wörter gesamt",
                    value: "\(viewModel.statistics.totalWords)"
                )
                Divider().frame(height: 40)
                StatCard(
                    title: "Wörter/Min",
                    value: String(format: "%.0f", viewModel.statistics.averageWPM)
                )
                Divider().frame(height: 40)
                StatCard(
                    title: "Verarbeitungszeit",
                    value: String(format: "%.0f ms", viewModel.statistics.averageProcessingTimeMs)
                )
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Streak

    private var streakSection: some View {
        GroupBox("Streak") {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(viewModel.statistics.currentStreakDays > 0 ? .orange : .secondary)
                VStack(alignment: .leading) {
                    Text("\(viewModel.statistics.currentStreakDays) Tage")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Aufeinanderfolgende Tage mit Diktaten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
