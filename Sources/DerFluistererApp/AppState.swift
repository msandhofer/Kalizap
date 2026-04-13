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
        FileLog.log("startPipeline — language=\(settings.audio.language.rawValue)")
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
    /// Language and noiseSuppressionEnabled need a restart — other settings
    /// like correction and sounds are read fresh per dictation.
    /// Uses Swift Observation directly — no SwiftUI dependency.
    private func observeSettingsChanges() {
        lastObservedNS = settings.audio.noiseSuppressionEnabled
        lastObservedLanguage = settings.audio.language
        scheduleObservation()
    }

    private var lastObservedNS: Bool = true
    private var lastObservedLanguage: SupportedLanguage = .de

    private func scheduleObservation() {
        withObservationTracking {
            _ = settings.audio.noiseSuppressionEnabled
            _ = settings.audio.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduleObservation()

                let newNS = self.settings.audio.noiseSuppressionEnabled
                let newLanguage = self.settings.audio.language
                if newNS != self.lastObservedNS || newLanguage != self.lastObservedLanguage {
                    FileLog.log("AppState — settings changed: language=\(newLanguage.rawValue) ns=\(newNS)")
                    self.lastObservedNS = newNS
                    self.lastObservedLanguage = newLanguage
                    await self.restartPipeline()
                }
            }
        }
    }
}
