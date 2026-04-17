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
        let container = try! ModelContainer(
            for: DictationRecord.self,
            migrationPlan: DictationMigrationPlan.self
        )
        let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
        _appState = State(initialValue: AppState(settings: settings, store: store))
        FileLog.log("App.init completed — language=\(settings.audio.language.rawValue)")
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

        Window("Einstellungen", id: "settings") {
            MainWindowView(appState: appState, updater: appState.updater)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 560)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsOpenButton()
            }
        }
    }
}

private struct SettingsOpenButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Einstellungen…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
