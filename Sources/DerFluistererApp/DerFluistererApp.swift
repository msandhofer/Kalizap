import SwiftUI
import SwiftData
import DerFluisterer

@main
struct DerFluistererApp: App {
    @State private var appState: AppState

    init() {
        let settings = SettingsManager(
            keychain: KeychainService(),
            apiKeyValidator: AnthropicAPIKeyValidator(),
            launchAtLogin: LaunchAtLoginService()
        )
        let container = try! ModelContainer(for: DictationRecord.self)
        let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
        _appState = State(initialValue: AppState(settings: settings, store: store))
        FileLog.log("App.init completed — model setting=\(settings.audio.whisperModel.rawValue)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: appState.settings, pipeline: appState.pipeline, updater: appState.updater, historyVM: appState.historyVM)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .task {
                    await appState.bootstrap()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            MainWindowView(settings: appState.settings, historyVM: appState.historyVM, statisticsVM: appState.statisticsVM, updater: appState.updater)
        }
    }
}
