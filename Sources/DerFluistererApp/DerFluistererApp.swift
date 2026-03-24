import SwiftUI
import SwiftData
import DerFluisterer

@main
struct DerFluistererApp: App {
    @State private var settings = SettingsManager(
        keychain: KeychainService(),
        apiKeyValidator: AnthropicAPIKeyValidator(),
        launchAtLogin: LaunchAtLoginService()
    )
    @State private var recordingVM = RecordingViewModel()
    @State private var historyVM: HistoryViewModel

    init() {
        let container = try! ModelContainer(for: DictationRecord.self)
        let store = DictationStoreImpl(modelContainer: container)
        _historyVM = State(initialValue: HistoryViewModel(store: store))
    }

    var body: some Scene {
        MenuBarExtra("DerFlüsterer", systemImage: menuBarIcon) {
            MenuBarView(settings: settings, recordingVM: recordingVM)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MainWindowView(settings: settings, historyVM: historyVM)
        }
    }

    private var menuBarIcon: String {
        if recordingVM.isRecording {
            return recordingVM.menuBarIcon
        }
        switch settings.apiKeyStatus {
        case .missing, .invalid:
            return "mic.fill.badge.xmark"
        case .validating:
            return "mic.fill.badge.plus"
        case .valid:
            return "mic.fill"
        }
    }
}
