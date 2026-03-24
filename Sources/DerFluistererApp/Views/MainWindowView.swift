import SwiftUI
import DerFluisterer

struct MainWindowView: View {
    @Bindable var settings: SettingsManager
    @Bindable var historyVM: HistoryViewModel
    @Bindable var statisticsVM: StatisticsViewModel

    var body: some View {
        TabView {
            HistoryView(viewModel: historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView(settings: settings)
                .tabItem { Label("Einstellungen", systemImage: "gear") }

            StatisticsView(viewModel: statisticsVM)
                .tabItem { Label("Statistiken", systemImage: "chart.bar") }
        }
        .frame(width: 560, height: 480)
    }
}
