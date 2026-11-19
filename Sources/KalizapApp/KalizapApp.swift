import SwiftUI
import SwiftData
import Kalizap

@main
struct KalizapApp: App {
    @State private var appState: AppState

    init() {
        let credentialStore = Self.makeCredentialStore()
        let settings = SettingsManager(
            credentialStore: credentialStore,
            apiKeyValidator: AnthropicAPIKeyValidator(),
            launchAtLogin: LaunchAtLoginService()
        )
        let container = DictationContainerFactory.makeContainer(
            storeURL: Self.supportDirectory.appendingPathComponent("Dictations.store")
        )
        let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
        _appState = State(initialValue: AppState(settings: settings, store: store))
        FileLog.log("App.init completed — language=\(settings.audio.language.rawValue)")
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Kalizap", isDirectory: true)
    }

    private static func makeCredentialStore() -> EncryptedCredentialStore {
        EncryptedCredentialStore(
            baseDirectory: supportDirectory,
            identity: ProductionHardwareIdentity(),
            appSecret: AppSecret.bytes
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: appState.settings, pipeline: appState.pipeline, historyVM: appState.historyVM, appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .task {
                    await appState.bootstrap()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Einstellungen", id: "settings") {
            MainWindowView(appState: appState)
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
