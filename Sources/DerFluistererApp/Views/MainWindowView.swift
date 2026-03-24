import SwiftUI
import DerFluisterer

struct MainWindowView: View {
    @Bindable var settings: SettingsManager
    @Bindable var historyVM: HistoryViewModel

    var body: some View {
        TabView {
            HistoryView(viewModel: historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView(settings: settings)
                .tabItem { Label("Einstellungen", systemImage: "gear") }

            StatisticsPlaceholderView()
                .tabItem { Label("Statistiken", systemImage: "chart.bar") }
        }
        .frame(width: 560, height: 480)
    }
}

struct StatisticsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Statistiken kommen in Issue #11")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
