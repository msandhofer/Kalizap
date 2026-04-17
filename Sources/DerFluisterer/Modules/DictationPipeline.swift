import Foundation
import os.log

extension Duration {
    var millisInt: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000) + Int(Double(attoseconds) / 1e15)
    }
}

private let logger = Logger(subsystem: "com.derfluesterer", category: "Pipeline")

/// Kleines Kontrakt für einen Overlay-Presenter, den die Pipeline beim
/// Aufnahme-Start öffnet und beim Stop schließt. Implementierung lebt in
/// der App-Schicht (NSPanel).
@MainActor
public protocol SpectrumOverlayPresenting: AnyObject {
    func show(pipeline: DictationPipeline)
    func hide()
}

/// File logger controlled by --verbose-log launch argument.
public enum FileLog {
    public static let enabled = CommandLine.arguments.contains("--verbose-log")
    private static let appender = FileAppender(
        url: FileManager.default.temporaryDirectory.appending(path: "derfluesterer-debug.log")
    )

    public static func log(_ message: String) {
        guard enabled else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        appender.append("[\(ts)] \(message)\n")
    }

    public static var path: String { appender.path }
}

/// Append-only file writer, extracted from FileLog for reuse and testability.
public final class FileAppender: @unchecked Sendable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var path: String { url.path }

    public func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

extension ContinuousClock.Instant {
    func millisecondsSinceNow() -> Int {
        let elapsed = ContinuousClock.now - self
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

public struct PipelineDependencies {
    public let hotkey: any HotkeyMonitoring
    public let recorder: any AudioCapturing
    public let metering: any AudioLevelMetering
    public let spectrumProvider: any AudioSpectrumProviding
    public let overlayPresenter: (any SpectrumOverlayPresenting)?
    public let transcriber: any TranscriptionEngine
    public let corrector: any TextCorrecting
    public let inserter: any TextInserting
    public let appDetector: any ActiveAppDetecting
    public let store: any DictationStoring
    public let sound: any SoundPlaying
    public let settings: SettingsManager

    public init(
        hotkey: any HotkeyMonitoring,
        recorder: any AudioCapturing,
        metering: any AudioLevelMetering,
        spectrumProvider: any AudioSpectrumProviding,
        overlayPresenter: (any SpectrumOverlayPresenting)? = nil,
        transcriber: any TranscriptionEngine,
        corrector: any TextCorrecting,
        inserter: any TextInserting,
        appDetector: any ActiveAppDetecting,
        store: any DictationStoring,
        sound: any SoundPlaying,
        settings: SettingsManager
    ) {
        self.hotkey = hotkey
        self.recorder = recorder
        self.metering = metering
        self.spectrumProvider = spectrumProvider
        self.overlayPresenter = overlayPresenter
        self.transcriber = transcriber
        self.corrector = corrector
        self.inserter = inserter
        self.appDetector = appDetector
        self.store = store
        self.sound = sound
        self.settings = settings
    }
}

private struct DictationJob {
    let buffer: CollectedAudioBuffer
    let stopTimestamp: ContinuousClock.Instant
    let correctionConfig: CorrectionConfig
    let language: SupportedLanguage
    let streamingResult: String
    let stopSoundMs: Int
    let recorderStopMs: Int
    let streamingWaitMs: Int
}

@Observable @MainActor
public final class DictationPipeline {
    private static let maxStateHistory = 50

    public private(set) var state: PipelineState = .idle {
        didSet {
            stateHistory.append(state)
            if stateHistory.count > Self.maxStateHistory {
                stateHistory.removeFirst(stateHistory.count - Self.maxStateHistory)
            }
            if case .error(let error) = state {
                lastError = error
            }
        }
    }
    public private(set) var latencyMs: Int?
    public private(set) var lastError: PipelineError?
    public private(set) var stateHistory: [PipelineState] = []
    public private(set) var streamingText: String = ""
    private var streamingFinalTranscription: FinalTranscription?
    public private(set) var audioLevel: Float = 0
    public private(set) var spectrumBands: [Float] = Array(repeating: 0, count: AudioSpectrumCalculator.bandCount)

    /// Called when correction falls back to raw text due to API error (e.g. missing/invalid key).
    public var onCorrectionFallback: (() -> Void)?

    private static let recordingTimeout: Duration = .seconds(120)

    private let deps: PipelineDependencies
    private var isRecording = false
    private var cancelled = false
    private var processingChain: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var recordingWatchdog: Task<Void, Never>?
    private var collectedChunks: [AudioChunk] = []

    public init(dependencies: PipelineDependencies) {
        self.deps = dependencies
    }

    public func activate() async {
        FileLog.log("Pipeline.activate — listening for hotkey events")
        for await event in deps.hotkey.events {
            FileLog.log("Pipeline.activate — event: \(event)")
            switch event {
            case .recordingStarted:
                await handleStart()
            case .recordingStopped:
                await handleStop()
            }
        }
    }

    public func loadModelAndActivate() async {
        let language = deps.settings.audio.language.transcriptionLanguage
        FileLog.log("loadModelAndActivate START — language=\(language)")
        FileLog.log("Task.isCancelled=\(Task.isCancelled)")
        state = .loadingModel(progress: 0)

        let estimatedDuration = Duration.seconds(5)
        let simulated = SimulatedProgress(estimatedDuration: estimatedDuration)

        let progressTask = Task.detached { @Sendable in
            for await progress in simulated.values {
                await MainActor.run { [weak self] in
                    self?.state = .loadingModel(progress: progress)
                }
            }
        }

        FileLog.log("Calling transcriber.loadModel...")
        do {
            try await deps.transcriber.loadModel(for: language) { _ in
                // Real progress ignored — using simulated progress instead
            }
            simulated.complete()
            await progressTask.value
            FileLog.log("loadModel SUCCESS")
        } catch {
            simulated.complete()
            progressTask.cancel()
            FileLog.log("loadModel FAILED: \(error)")
            FileLog.log("Task.isCancelled after error=\(Task.isCancelled)")
            state = .error(PipelineError(message: "Modell konnte nicht geladen werden: \(error.localizedDescription)", isRecoverable: true))
            return
        }

        do {
            try await deps.hotkey.start()
        } catch {
            state = .error(PipelineError(message: "Accessibility-Berechtigung fehlt. Bitte in Systemeinstellungen aktivieren.", isRecoverable: true))
            return
        }

        state = .idle
        await activate()
    }

    public func deactivate() {
        shutdown()
        deps.hotkey.stop()
        Task { await deps.recorder.stopRecording() }
    }

    /// Live-Rebind des Hotkeys. Setzt die neue Konfiguration auf dem Dispatcher,
    /// ohne den CGEventTap neu zu installieren. Greift sofort.
    public func updateHotkey(_ configuration: HotkeyConfiguration) {
        guard let configuring = deps.hotkey as? any HotkeyConfiguring else {
            FileLog.log("updateHotkey — hotkey unterstuetzt kein HotkeyConfiguring, ignoriert")
            return
        }
        configuring.updateConfiguration(configuration)
        FileLog.log("updateHotkey — neuer Hotkey: keyCode=\(configuration.keyCode)")
    }

    public func startDictation() async {
        await handleStart()
    }

    public func stopDictation() async {
        await handleStop()
    }

    public func cancelDictation() {
        shutdown()
    }

    /// Deterministic shutdown sequence shared by deactivate() and cancelDictation().
    /// Order: 1) flag cancel 2) stop watchdog 3) stop streaming/metering
    /// 4) cancel processing chain 5) cancel transcriber 6) clear buffers 7) reset state
    private func shutdown() {
        cancelled = true
        isRecording = false
        recordingWatchdog?.cancel()
        stopStreamingAndMetering()
        processingChain?.cancel()
        processingChain = nil
        deps.transcriber.cancel()
        collectedChunks = []
        state = .idle
    }

    public func dismissError() {
        if case .error = state {
            state = .idle
        }
    }

    // MARK: - Private

    private func stopStreamingAndMetering() {
        streamingTask?.cancel()
        streamingTask = nil
        levelTask?.cancel()
        levelTask = nil
        deps.spectrumProvider.setSpectrumHandler(nil)
        audioLevel = 0
        spectrumBands = Array(repeating: 0, count: AudioSpectrumCalculator.bandCount)
        deps.overlayPresenter?.hide()
    }

    private func handleStart() async {
        FileLog.log("handleStart — begin")
        cancelled = false
        isRecording = true
        streamingText = ""
        streamingFinalTranscription = nil
        collectedChunks = []
        state = .recording
        startRecordingWatchdog()
        await deps.sound.playStartSound()
        do {
            FileLog.log("handleStart — calling recorder.startRecording")
            try await deps.recorder.startRecording()
            FileLog.log("handleStart — recorder started, starting audio processing + metering")
            startAudioProcessing()
            startLevelMetering()
            deps.spectrumProvider.setSpectrumHandler { [weak self] bands in
                Task { @MainActor in
                    self?.spectrumBands = bands
                }
            }
            deps.overlayPresenter?.show(pipeline: self)
            FileLog.log("handleStart — done")
        } catch {
            FileLog.log("handleStart — ERROR: \(error)")
            isRecording = false
            recordingWatchdog?.cancel()
            state = .error(PipelineError(message: error.localizedDescription, isRecoverable: true))
        }
    }

    private func startRecordingWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.recordingTimeout)
            guard let self, !Task.isCancelled, self.isRecording else { return }
            await self.handleStop()
        }
    }

    private func stopLevelMetering() {
        levelTask?.cancel()
        levelTask = nil
        deps.spectrumProvider.setSpectrumHandler(nil)
        audioLevel = 0
        spectrumBands = Array(repeating: 0, count: AudioSpectrumCalculator.bandCount)
        deps.overlayPresenter?.hide()
    }

    private func handleStop() async {
        FileLog.log("handleStop — begin, isRecording=\(isRecording)")
        recordingWatchdog?.cancel()
        let stopTimestamp = ContinuousClock.now
        isRecording = false

        stopLevelMetering()

        let tSound = ContinuousClock.now
        await deps.sound.playStopSound()
        let stopSoundMs = (ContinuousClock.now - tSound).millisInt

        let tRecorder = ContinuousClock.now
        await deps.recorder.stopRecording()
        let recorderStopMs = (ContinuousClock.now - tRecorder).millisInt
        FileLog.log("handleStop — recorder stopped in \(recorderStopMs)ms, waiting for streaming final decode")

        let tStreaming = ContinuousClock.now
        await streamingTask?.value
        streamingTask = nil
        let streamingWaitMs = (ContinuousClock.now - tStreaming).millisInt
        FileLog.log("handleStop — streaming wait \(streamingWaitMs)ms, streamingText=\(streamingText.prefix(50))...")

        let buffer = collectBuffer()
        FileLog.log("handleStop — buffer: \(buffer.samples.count) samples, \(String(format: "%.1f", buffer.totalDuration))s, streamingText=\(streamingText.prefix(50))...")
        guard !buffer.samples.isEmpty else {
            FileLog.log("handleStop — empty buffer, going idle")
            state = .idle
            return
        }

        let job = DictationJob(
            buffer: buffer,
            stopTimestamp: stopTimestamp,
            correctionConfig: buildCorrectionConfig(),
            language: deps.settings.audio.language,
            streamingResult: streamingText,
            stopSoundMs: stopSoundMs,
            recorderStopMs: recorderStopMs,
            streamingWaitMs: streamingWaitMs
        )
        FileLog.log("handleStop — job created, queueing process")

        // Chain processing: wait for previous dictation to finish, then process this one
        let previousChain = processingChain
        processingChain = Task { [weak self] in
            await previousChain?.value
            await self?.process(job)
        }
    }

    private func collectBuffer() -> CollectedAudioBuffer {
        let chunks = collectedChunks
        collectedChunks = []
        return CollectedAudioBuffer(
            samples: chunks.flatMap { $0.samples },
            sampleRate: chunks.first?.sampleRate ?? AudioProcessingUtils.transcriptionSampleRate,
            totalDuration: chunks.reduce(0.0) { $0 + $1.duration }
        )
    }

    private func buildCorrectionConfig() -> CorrectionConfig {
        deps.settings.correction.buildCorrectionConfig(
            frontmostApp: deps.appDetector.frontmostApp()
        )
    }

    private func startAudioProcessing() {
        let recorder = deps.recorder

        streamingTask = Task { [weak self] in
            guard let self else { return }
            let config = TranscriptionConfig(language: self.deps.settings.audio.language)
            let audioStream = self.bridgeAudioStream(from: recorder)

            let results = self.deps.transcriber.transcribe(audioStream, config: config)
            for await result in results {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.streamingText = result.text
                    if case .final(let ft) = result {
                        self.streamingFinalTranscription = ft
                    }
                }
            }
        }
    }

    /// Bridges the recorder's AsyncThrowingStream to an AsyncStream,
    /// collecting chunks for batch fallback along the way.
    private func bridgeAudioStream(from recorder: any AudioCapturing) -> AsyncStream<AudioChunk> {
        AsyncStream<AudioChunk> { continuation in
            Task { [weak self] in
                do {
                    for try await chunk in recorder.audioStream {
                        await MainActor.run { self?.collectedChunks.append(chunk) }
                        continuation.yield(chunk)
                    }
                } catch {
                    // Stream ended (device lost, etc.)
                }
                continuation.finish()
            }
        }
    }

    private func startLevelMetering() {
        let metering = deps.metering

        levelTask = Task { [weak self] in
            guard let self else { return }
            await metering.startMetering()
            for await level in metering.levelStream {
                if Task.isCancelled { break }
                await MainActor.run { self.audioLevel = level.average }
            }
        }
    }

    private struct StageTimings {
        var normalizationMs: Int = 0
        var transcriptionMs: Int = 0
        var correctionMs: Int = 0
        var insertionMs: Int = 0
        var usedStreamingResult: Bool = false
        var audioSampleCount: Int = 0
        var stopSoundMs: Int = 0
        var recorderStopMs: Int = 0
        var streamingWaitMs: Int = 0
    }

    private func process(_ job: DictationJob) async {
        FileLog.log("process — begin, cancelled=\(cancelled)")
        guard !cancelled else {
            FileLog.log("process — cancelled, aborting")
            return
        }

        var timings = StageTimings()
        timings.audioSampleCount = job.buffer.samples.count
        timings.usedStreamingResult = !job.streamingResult.isEmpty
        timings.stopSoundMs = job.stopSoundMs
        timings.recorderStopMs = job.recorderStopMs
        timings.streamingWaitMs = job.streamingWaitMs

        // 1. Transcribe
        let t1 = ContinuousClock.now
        guard let transcription = await performTranscription(job) else { return }
        let transcriptionElapsed = ContinuousClock.now - t1

        if case .final(let ft) = transcription {
            timings.normalizationMs = ft.normalizationTime.millisInt
            timings.transcriptionMs = ft.processingTime.millisInt
        } else {
            timings.transcriptionMs = transcriptionElapsed.millisInt
        }

        // 2. Correct
        let t2 = ContinuousClock.now
        let correctionOutcome = await applyCorrection(job, transcription: transcription)
        timings.correctionMs = (ContinuousClock.now - t2).millisInt
        guard !cancelled else { return }

        let correctedText = correctionOutcome.text
        guard !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            FileLog.log("process — empty transcription, skipping insert + persist")
            updateStateIfNotRecording(.idle)
            return
        }

        // 3. Notify on correction fallback — but not when the user deliberately
        // disabled the LLM via tasks (that's not an error condition).
        switch correctionOutcome {
        case .fallbackRaw(_, .llmDisabled), .corrected:
            break
        case .fallbackRaw:
            onCorrectionFallback?()
        }

        // 4. Insert
        let t3 = ContinuousClock.now
        let insertionResult = await insertText(correctedText)
        timings.insertionMs = (ContinuousClock.now - t3).millisInt
        guard !cancelled else { return }

        // 5. Persist + finalize
        let t4 = ContinuousClock.now
        await persistResult(job, rawText: transcription.text, correctedText: correctedText, insertionResult: insertionResult, timings: timings)
        let persistMs = (ContinuousClock.now - t4).millisInt

        FileLog.log("process — overhead breakdown: stopSound=\(job.stopSoundMs)ms recorder=\(job.recorderStopMs)ms streamingWait=\(job.streamingWaitMs)ms persist=\(persistMs)ms")
    }

    private func performTranscription(_ job: DictationJob) async -> TranscriptionResult? {
        deps.corrector.updateConfig(job.correctionConfig)

        let useStreaming = !job.streamingResult.isEmpty
        FileLog.log("process — transcribing (useStreaming=\(useStreaming))")
        updateStateIfNotRecording(.processing(stage: .transcribing))

        let transcription: TranscriptionResult?
        if useStreaming, let ft = streamingFinalTranscription {
            transcription = .final(ft)
        } else if useStreaming {
            transcription = .final(FinalTranscription(
                text: job.streamingResult,
                segments: [],
                processingTime: .zero
            ))
        } else {
            transcription = await transcribeBatch(buffer: job.buffer, language: job.language)
        }

        guard !cancelled, let transcription else {
            FileLog.log("process — transcription failed or cancelled")
            if !cancelled {
                state = .error(PipelineError(message: "Transcription failed", isRecoverable: true))
            }
            return nil
        }
        FileLog.log("process — transcribed: \(transcription.text.prefix(50))...")
        return transcription
    }

    private func applyCorrection(_ job: DictationJob, transcription: TranscriptionResult) async -> CorrectionOutcome {
        guard !job.correctionConfig.tasks.isEmpty else {
            FileLog.log("process — LLM-Korrektur deaktiviert (keine Aufgaben aktiv), Rohtext wird eingefuegt")
            return .fallbackRaw(text: transcription.text, reason: .llmDisabled)
        }
        FileLog.log("process — correcting")
        updateStateIfNotRecording(.processing(stage: .correcting))
        let outcome = await deps.corrector.correct(transcription)
        FileLog.log("process — corrected: \(outcome.text.prefix(50))...")
        return outcome
    }

    private func insertText(_ text: String) async -> InsertionResult {
        FileLog.log("process — inserting")
        updateStateIfNotRecording(.processing(stage: .inserting))
        let result = await deps.inserter.insert(text)
        FileLog.log("process — inserted: \(result.outcome)")
        return result
    }

    private func persistResult(_ job: DictationJob, rawText: String, correctedText: String, insertionResult: InsertionResult, timings: StageTimings) async {
        let measuredLatencyMs = job.stopTimestamp.millisecondsSinceNow()
        latencyMs = measuredLatencyMs

        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: rawText,
            correctedText: correctedText,
            language: job.language.rawValue,
            contextMode: job.correctionConfig.contextMode.rawValue,
            targetApp: deps.appDetector.frontmostApp()?.localizedName,
            durationMs: Int(job.buffer.totalDuration * 1000),
            processingTimeMs: measuredLatencyMs,
            normalizationMs: timings.normalizationMs,
            transcriptionMs: timings.transcriptionMs,
            correctionMs: timings.correctionMs,
            insertionMs: timings.insertionMs,
            usedStreamingResult: timings.usedStreamingResult,
            audioSampleCount: timings.audioSampleCount,
            stopSoundMs: timings.stopSoundMs,
            recorderStopMs: timings.recorderStopMs,
            streamingWaitMs: timings.streamingWaitMs
        )
        try? await deps.store.save(entry)

        if case .pendingInClipboard = insertionResult.outcome {
            updateStateIfNotRecording(.pendingInClipboard)
        } else {
            updateStateIfNotRecording(.idle)
        }
    }

    private func updateStateIfNotRecording(_ newState: PipelineState) {
        if !isRecording {
            state = newState
        }
    }

    private func transcribeBatch(buffer: CollectedAudioBuffer, language: SupportedLanguage) async -> TranscriptionResult? {
        FileLog.log("transcribeBatch — \(buffer.samples.count) samples, \(String(format: "%.1f", buffer.totalDuration))s")
        let chunk = AudioChunk(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate,
            timestamp: 0,
            duration: buffer.totalDuration,
            level: AudioLevel(average: 0, peak: 0, timestamp: 0)
        )
        let stream = AsyncStream<AudioChunk> { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
        let config = TranscriptionConfig(language: language)
        let results = deps.transcriber.transcribe(stream, config: config)

        var lastResult: TranscriptionResult?
        for await result in results {
            if cancelled {
                FileLog.log("transcribeBatch — cancelled during iteration")
                return nil
            }
            FileLog.log("transcribeBatch — got result: \(result.text.prefix(50))")
            lastResult = result
        }
        FileLog.log("transcribeBatch — finished, hasResult=\(lastResult != nil)")
        return lastResult
    }
}
