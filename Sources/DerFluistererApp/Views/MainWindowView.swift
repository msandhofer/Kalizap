import AppKit
import SwiftUI
import DerFluisterer

struct MainWindowView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            HistoryView(viewModel: appState.historyVM)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView(settings: appState.settings, appState: appState)
                .tabItem { Label("Einstellungen", systemImage: "gear") }

            StatisticsView(viewModel: appState.statisticsVM)
                .tabItem { Label("Statistiken", systemImage: "chart.bar") }
        }
        .frame(
            minWidth: 560, idealWidth: 600, maxWidth: .infinity,
            minHeight: 480, idealHeight: 560, maxHeight: .infinity
        )
        .onAppear {
            // Force the Settings window to become key so controls render in their
            // active (colored) state instead of greyed-out "inactive" appearance.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
