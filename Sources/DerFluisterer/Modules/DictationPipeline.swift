import Foundation

extension ContinuousClock.Instant {
    func millisecondsSinceNow() -> Int {
        let elapsed = ContinuousClock.now - self
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

public protocol SoundPlaying: Sendable {
    func playStartSound() async
    func playStopSound() async
}

public struct PipelineDependencies {
    public let hotkey: any HotkeyMonitoring
    public let recorder: any AudioCapturing
    public let metering: any AudioLevelMetering
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
    public private(set) var audioLevel: Float = 0

    private let deps: PipelineDependencies
    private var isRecording = false
    private var cancelled = false
    private var processingChain: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var collectedChunks: [AudioChunk] = []

    public init(dependencies: PipelineDependencies) {
        self.deps = dependencies
    }

    public func activate() async {
        for await event in deps.hotkey.events {
            switch event {
            case .recordingStarted:
                await handleStart()
            case .recordingStopped:
                await handleStop()
            }
        }
    }

    public func loadModelAndActivate() async {
        let language = TranscriptionLanguage(rawValue: deps.settings.audio.language.rawValue) ?? .german
        state = .loadingModel(progress: 0)
        do {
            try await deps.transcriber.loadModel(for: language) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .loadingModel(progress: progress)
                }
            }
        } catch {
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
        cancelDictation()
    }

    public func startDictation() async {
        await handleStart()
    }

    public func stopDictation() async {
        await handleStop()
    }

    public func cancelDictation() {
        cancelled = true
        isRecording = false
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
        audioLevel = 0
    }

    private func handleStart() async {
        cancelled = false
        isRecording = true
        streamingText = ""
        collectedChunks = []
        state = .recording
        await deps.sound.playStartSound()
        do {
            try await deps.recorder.startRecording()
            startAudioProcessing()
            startLevelMetering()
        } catch {
            isRecording = false
            state = .error(PipelineError(message: error.localizedDescription, isRecoverable: true))
        }
    }

    private func handleStop() async {
        let stopTimestamp = ContinuousClock.now
        isRecording = false

        stopStreamingAndMetering()

        await deps.sound.playStopSound()
        await deps.recorder.stopRecording()

        let buffer = collectBuffer()
        guard !buffer.samples.isEmpty else {
            state = .idle
            return
        }

        let job = DictationJob(
            buffer: buffer,
            stopTimestamp: stopTimestamp,
            correctionConfig: buildCorrectionConfig(),
            language: deps.settings.audio.language,
            streamingResult: streamingText
        )

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
            sampleRate: chunks.first?.sampleRate ?? 16000,
            totalDuration: chunks.reduce(0.0) { $0 + $1.duration }
        )
    }

    private func buildCorrectionConfig() -> CorrectionConfig {
        let correctionSettings = deps.settings.correction
        return CorrectionConfig(
            from: correctionSettings,
            resolvedContextMode: resolveContextMode(correctionSettings)
        )
    }

    private func startAudioProcessing() {
        let recorder = deps.recorder

        // Single consumer of audioStream: collects chunks AND feeds transcriber
        streamingTask = Task { [weak self] in
            guard let self else { return }
            let config = TranscriptionConfig(language: self.deps.settings.audio.language)

            // Bridge AsyncThrowingStream to AsyncStream, collecting chunks along the way
            let audioStream = AsyncStream<AudioChunk> { continuation in
                Task { [weak self] in
                    do {
                        for try await chunk in recorder.audioStream {
                            // Collect for batch fallback
                            await MainActor.run { self?.collectedChunks.append(chunk) }
                            // Forward to transcriber
                            continuation.yield(chunk)
                        }
                    } catch {
                        // Stream ended (device lost, etc.)
                    }
                    continuation.finish()
                }
            }

            let results = self.deps.transcriber.transcribe(audioStream, config: config)
            for await result in results {
                if Task.isCancelled { return }
                await MainActor.run { self.streamingText = result.text }
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

    private func process(_ job: DictationJob) async {
        guard !cancelled else { return }

        deps.corrector.updateConfig(job.correctionConfig)

        // Transcribe: use streaming result if available, otherwise batch
        updateStateIfNotRecording(.processing(stage: .transcribing))
        let transcription: TranscriptionResult?

        if !job.streamingResult.isEmpty {
            transcription = .final(FinalTranscription(
                text: job.streamingResult,
                segments: [],
                processingTime: .zero
            ))
        } else {
            transcription = await transcribeBatch(buffer: job.buffer, language: job.language)
        }

        guard !cancelled, let transcription else {
            if !cancelled {
                state = .error(PipelineError(message: "Transcription failed", isRecoverable: true))
            }
            return
        }

        // Correct
        updateStateIfNotRecording(.processing(stage: .correcting))
        let correctionOutcome = await deps.corrector.correct(transcription)

        guard !cancelled else { return }

        let rawText = transcription.text
        let correctedText = correctionOutcome.text

        // Insert
        updateStateIfNotRecording(.processing(stage: .inserting))
        let insertionResult = await deps.inserter.insert(correctedText)

        guard !cancelled else { return }

        // Measure latency (key-release → insertion complete)
        let measuredLatencyMs = job.stopTimestamp.millisecondsSinceNow()
        latencyMs = measuredLatencyMs

        // Persist
        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: rawText,
            correctedText: correctedText,
            language: job.language.rawValue,
            contextMode: job.correctionConfig.contextMode.rawValue,
            targetApp: deps.appDetector.frontmostApp()?.localizedName,
            durationMs: Int(job.buffer.totalDuration * 1000),
            processingTimeMs: measuredLatencyMs
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

    private func resolveContextMode(_ settings: CorrectionSettings) -> ContextMode {
        guard settings.contextMode == .auto else {
            return settings.contextMode
        }
        if let app = deps.appDetector.frontmostApp(),
           let appMode = settings.appMapping[app.bundleIdentifier] {
            return appMode
        }
        return .neutral
    }

    private func transcribeBatch(buffer: CollectedAudioBuffer, language: SupportedLanguage) async -> TranscriptionResult? {
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
            if cancelled { return nil }
            lastResult = result
        }
        return lastResult
    }
}
