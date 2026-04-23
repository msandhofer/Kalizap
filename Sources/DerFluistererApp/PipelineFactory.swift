import AppKit
import Foundation
import DerFluisterer

@MainActor
enum PipelineFactory {

    static func makePipeline(
        settings: SettingsManager,
        store: any DictationStoring
    ) async -> DictationPipeline {
        // Framework lazy-init: instantiating NSSound here loads AudioToolbox
        // and the NSSound machinery into the process. The HW isn't woken, but
        // the first real NSSound.play() later skips the ~500–1000ms framework
        // initialization. See docs/audio-cold-start/.
        primeAudioToolboxFramework()

        let appDetector = NSWorkspaceAppDetector()
        let hotkey = HotkeyManagerImpl(configuration: settings.hotkey.configuration)
        let noiseSuppressor = await loadNoiseSuppressor(enabled: settings.audio.noiseSuppressionEnabled)

        let recorder = AudioRecorderImpl(noiseSuppressor: noiseSuppressor)
        let transcriber = SpeechAnalyzerTranscriptionEngine()
        let corrector = makeCorrector(settings: settings)
        let inserter = TextInserterImpl(
            clipboard: NSPasteboardClipboardManager(),
            keystroke: CGEventKeystrokeSimulator(),
            accessibility: AXAccessibilityInserter(),
            appDetector: appDetector
        )
        let sound = SoundPlayer(
            backend: SystemSoundBackend(),
            isEnabled: { [settings] in settings.audio.soundsEnabled }
        )
        let audioMonitor = SystemAudioActivityMonitor()

        let deps = PipelineDependencies(
            hotkey: hotkey,
            recorder: recorder,
            metering: recorder,
            spectrumProvider: recorder,
            overlayPresenter: SpectrumOverlayWindow.shared,
            transcriber: transcriber,
            corrector: corrector,
            inserter: inserter,
            appDetector: appDetector,
            store: store,
            sound: sound,
            audioMonitor: audioMonitor,
            settings: settings
        )

        return DictationPipeline(dependencies: deps)
    }

    // MARK: - Framework Priming

    private static func primeAudioToolboxFramework() {
        let t0 = ContinuousClock.now
        _ = NSSound(named: "Tink")
        FileLog.log("TIMING PipelineFactory — AudioToolbox framework primed in \(t0.millisecondsSinceNow())ms")
    }

    // MARK: - Private

    private static func loadNoiseSuppressor(enabled: Bool) async -> DeepFilterProcessor? {
        guard enabled else { return nil }
        guard let modelURL = Bundle.module.url(forResource: "DeepFilterNet3_onnx", withExtension: "tar.gz") else {
            FileLog.log("PipelineFactory — DeepFilterNet3 model not found in bundle")
            return nil
        }
        let tStart = ContinuousClock.now
        return await Task.detached(priority: .userInitiated) {
            do {
                let processor = try DeepFilterProcessor(modelPath: modelURL.path)
                FileLog.log("TIMING PipelineFactory — DeepFilterNet3 loaded in \(tStart.millisecondsSinceNow())ms")
                return processor
            } catch {
                FileLog.log("PipelineFactory — DeepFilterNet3 load failed: \(error)")
                return nil
            }
        }.value
    }

    private static func makeCorrector(settings: SettingsManager) -> TextCorrectorImpl {
        let apiKeyProvider: @Sendable () throws -> String = { [settings] in
            try settings.resolveAPIKeySendable()
        }
        let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: apiKeyProvider)
        return TextCorrectorImpl(
            config: CorrectionConfig(),
            transport: transport,
            apiKeyProvider: apiKeyProvider
        )
    }
}
