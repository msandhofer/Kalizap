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
    @State private var historyVM: HistoryViewModel
    @State private var statisticsVM: StatisticsViewModel
    @State private var pipeline: DictationPipeline?
    @State private var updater: SparkleUpdater?
    @State private var apiKeyValidated = false

    private let store: any DictationStoring

    init() {
        let container = try! ModelContainer(for: DictationRecord.self)
        let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
        self.store = store
        _historyVM = State(initialValue: HistoryViewModel(store: store))
        _statisticsVM = State(initialValue: StatisticsViewModel(store: store))
        FileLog.log("App.init completed — model setting=\(settings.audio.whisperModel.rawValue)")
    }

    var body: some Scene {
        MenuBarExtra("DerFlüsterer", systemImage: menuBarIcon) {
            MenuBarView(settings: settings, pipeline: pipeline, updater: updater, historyVM: historyVM)
                .task {
                    FileLog.log(".task fired — pipeline=\(pipeline == nil ? "nil" : "exists")")
                    if updater == nil {
                        let u = SparkleUpdater(settings: settings)
                        updater = u
                        u.start()
                    }
                    guard pipeline == nil else { return }
                    // Unstructured Task: survives SwiftUI view recreation
                    // (menuBarIcon changes cause .task cancellation)
                    Task {
                        if !apiKeyValidated {
                            apiKeyValidated = true
                            await settings.validateAPIKey()
                        }
                        await startPipeline()
                    }
                }
                .onChange(of: settings.audio.whisperModel) {
                    FileLog.log(".onChange(whisperModel) fired — new value=\(settings.audio.whisperModel.rawValue)")
                    Task { await restartPipeline() }
                }
                .onChange(of: settings.audio.noiseSuppressionEnabled) {
                    FileLog.log(".onChange(noiseSuppression) fired — enabled=\(settings.audio.noiseSuppressionEnabled)")
                    Task { await restartPipeline() }
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            MainWindowView(settings: settings, historyVM: historyVM, statisticsVM: statisticsVM)
        }
    }

    @MainActor
    private func restartPipeline() async {
        FileLog.log("restartPipeline — deactivating old pipeline")
        pipeline?.deactivate()
        pipeline = nil
        FileLog.log("restartPipeline — starting new pipeline")
        await startPipeline()
    }

    @MainActor
    private func startPipeline() async {
        let modelRawValue = settings.audio.whisperModel.rawValue
        FileLog.log("startPipeline — model=\(modelRawValue) whisperModel=\(settings.audio.whisperModel)")
        let appDetector = NSWorkspaceAppDetector()
        let hotkey = HotkeyManagerImpl(configuration: settings.hotkey.configuration)

        var noiseSuppressor: DeepFilterProcessor? = nil
        if settings.audio.noiseSuppressionEnabled {
            if let modelURL = Bundle.module.url(forResource: "DeepFilterNet3_onnx", withExtension: "tar.gz") {
                // Load on background thread — df_create is CPU-intensive (~30s)
                noiseSuppressor = await Task.detached(priority: .userInitiated) {
                    do {
                        let processor = try DeepFilterProcessor(modelPath: modelURL.path)
                        FileLog.log("startPipeline — DeepFilterNet3 loaded")
                        return processor
                    } catch {
                        FileLog.log("startPipeline — DeepFilterNet3 load failed: \(error)")
                        return nil
                    }
                }.value
            } else {
                FileLog.log("startPipeline — DeepFilterNet3 model not found in bundle")
            }
        }

        let recorder = AudioRecorderImpl(noiseSuppressor: noiseSuppressor)
        let backend = WhisperKitBackend(model: modelRawValue)
        let transcriber = WhisperTranscriptionEngine(backend: backend)
        let apiKeyProvider: @Sendable () throws -> String = { [settings] in
            try settings.resolveAPIKeySendable()
        }
        let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: apiKeyProvider)
        let corrector = TextCorrectorImpl(
            config: CorrectionConfig(),
            transport: transport,
            apiKeyProvider: apiKeyProvider
        )
        let inserter = TextInserterImpl(
            clipboard: NSPasteboardClipboardManager(),
            keystroke: CGEventKeystrokeSimulator(),
            accessibility: AXAccessibilityInserter(),
            appDetector: appDetector
        )
        let sound = SoundPlayer(
            backend: SystemSoundBackend(),
            soundsEnabled: settings.audio.soundsEnabled
        )

        let deps = PipelineDependencies(
            hotkey: hotkey,
            recorder: recorder,
            metering: recorder,
            transcriber: transcriber,
            corrector: corrector,
            inserter: inserter,
            appDetector: appDetector,
            store: store,
            sound: sound,
            settings: settings
        )

        let p = DictationPipeline(dependencies: deps)
        pipeline = p
        await p.loadModelAndActivate()
    }

    private var menuBarIcon: String {
        if let pipeline {
            switch pipeline.state {
            case .loadingModel:
                return "arrow.down.circle"
            case .recording:
                return "waveform"
            case .processing:
                return "ellipsis.circle"
            case .error:
                return "mic.fill.badge.xmark"
            case .idle, .pendingInClipboard:
                break
            }
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
