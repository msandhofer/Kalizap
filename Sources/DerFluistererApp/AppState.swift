import Foundation
import DerFluisterer

@Observable @MainActor
final class AppState {
    private(set) var pipeline: DictationPipeline?
    private(set) var updater: SparkleUpdater?

    let settings: SettingsManager
    let historyVM: HistoryViewModel
    let statisticsVM: StatisticsViewModel

    private let store: any DictationStoring
    private var bootstrapped = false
    private var apiKeyToastShown = false

    init(settings: SettingsManager, store: any DictationStoring) {
        self.settings = settings
        self.store = store
        self.historyVM = HistoryViewModel(store: store)
        self.statisticsVM = StatisticsViewModel(store: store)
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        let u = SparkleUpdater(settings: settings)
        updater = u
        u.start()

        await settings.validateAPIKey()
        await startPipeline()

        observeSettingsChanges()
    }

    func restartPipeline() async {
        FileLog.log("restartPipeline — deactivating old pipeline")
        pipeline?.deactivate()
        pipeline = nil
        FileLog.log("restartPipeline — starting new pipeline")
        await startPipeline()
    }

    var menuBarIcon: String {
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

    // MARK: - Private

    private func startPipeline() async {
        FileLog.log("startPipeline — model=\(settings.audio.whisperModel.rawValue) engine=\(settings.audio.whisperEngine.rawValue)")
        let p = await PipelineFactory.makePipeline(settings: settings, store: store)

        p.onCorrectionFallback = { [weak self] in
            Task { @MainActor in
                self?.showAPIKeyToastIfNeeded()
            }
        }

        pipeline = p
        await p.loadModelAndActivate()
    }

    private func showAPIKeyToastIfNeeded() {
        guard !apiKeyToastShown else { return }
        guard settings.correction.showAPIKeyNotification else { return }
        apiKeyToastShown = true

        let message: String
        switch settings.apiKeyStatus {
        case .missing:
            message = "Kein API-Key konfiguriert — Text wird ohne Korrektur eingefügt."
        case .invalid(let detail):
            message = "API-Key ungültig (\(detail)) — Text wird ohne Korrektur eingefügt."
        default:
            message = "API-Korrektur fehlgeschlagen — Text wird ohne Korrektur eingefügt."
        }
        ToastWindow.show(message: message)
    }

    /// Observe settings that require a pipeline restart.
    /// Only whisperModel and noiseSuppressionEnabled need a restart — other settings
    /// like language, correction, and sounds are read fresh per dictation.
    /// Uses Swift Observation directly — no SwiftUI dependency.
    private func observeSettingsChanges() {
        lastObservedModel = settings.audio.whisperModel
        lastObservedNS = settings.audio.noiseSuppressionEnabled
        lastObservedEngine = settings.audio.whisperEngine
        lastObservedCoreML = settings.audio.useCoreML
        scheduleObservation()
    }

    private var lastObservedModel: WhisperModel = .largeV3Turbo
    private var lastObservedNS: Bool = true
    private var lastObservedEngine: WhisperEngine = .whisperCpp
    private var lastObservedCoreML: Bool = false

    private func scheduleObservation() {
        withObservationTracking {
            _ = settings.audio.whisperModel
            _ = settings.audio.noiseSuppressionEnabled
            _ = settings.audio.whisperEngine
            _ = settings.audio.useCoreML
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Re-register BEFORE async work so changes during restart aren't missed
                self.scheduleObservation()

                let newModel = self.settings.audio.whisperModel
                let newNS = self.settings.audio.noiseSuppressionEnabled
                let newEngine = self.settings.audio.whisperEngine
                let newCoreML = self.settings.audio.useCoreML
                if newModel != self.lastObservedModel || newNS != self.lastObservedNS || newEngine != self.lastObservedEngine || newCoreML != self.lastObservedCoreML {
                    FileLog.log("AppState — settings changed: model=\(newModel.rawValue) engine=\(newEngine.rawValue) ns=\(newNS) coreml=\(newCoreML)")
                    self.lastObservedModel = newModel
                    self.lastObservedNS = newNS
                    self.lastObservedEngine = newEngine
                    self.lastObservedCoreML = newCoreML
                    await self.restartPipeline()
                }
            }
        }
    }
}
