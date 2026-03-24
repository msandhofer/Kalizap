import Foundation

extension ContinuousClock.Instant {
    func millisecondsSinceNow() -> Int {
        let elapsed = ContinuousClock.now - self
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

protocol SoundPlaying: Sendable {
    func playStartSound() async
    func playStopSound() async
}

struct PipelineDependencies {
    let hotkey: any HotkeyMonitoring
    let recorder: any AudioCapturing
    let metering: any AudioLevelMetering
    let transcriber: any TranscriptionEngine
    let corrector: any TextCorrecting
    let inserter: any TextInserting
    let appDetector: any ActiveAppDetecting
    let store: any DictationStoring
    let sound: any SoundPlaying
    let settings: SettingsManager
}

private struct DictationJob {
    let buffer: CollectedAudioBuffer
    let stopTimestamp: ContinuousClock.Instant
    let correctionConfig: CorrectionConfig
    let language: SupportedLanguage
    let streamingResult: String
}

@Observable @MainActor
final class DictationPipeline {
    private static let maxStateHistory = 50

    private(set) var state: PipelineState = .idle {
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
    private(set) var latencyMs: Int?
    private(set) var lastError: PipelineError?
    private(set) var stateHistory: [PipelineState] = []
    private(set) var streamingText: String = ""
    private(set) var audioLevel: Float = 0

    private let deps: PipelineDependencies
    private var isRecording = false
    private var cancelled = false
    private var processingChain: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var collectedChunks: [AudioChunk] = []

    init(dependencies: PipelineDependencies) {
        self.deps = dependencies
    }

    func activate() async {
        for await event in deps.hotkey.events {
            switch event {
            case .recordingStarted:
                await handleStart()
            case .recordingStopped:
                await handleStop()
            }
        }
    }

    func deactivate() {
        cancelDictation()
    }

    func startDictation() async {
        await handleStart()
    }

    func stopDictation() async {
        await handleStop()
    }

    func cancelDictation() {
        cancelled = true
        isRecording = false
        stopStreamingAndMetering()
        processingChain?.cancel()
        processingChain = nil
        deps.transcriber.cancel()
        collectedChunks = []
        state = .idle
    }

    func dismissError() {
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
        let record = DictationRecord(
            rawTranscript: rawText,
            correctedText: correctedText,
            language: job.language.rawValue,
            contextMode: job.correctionConfig.contextMode.rawValue,
            targetApp: deps.appDetector.frontmostApp()?.localizedName,
            durationMs: Int(job.buffer.totalDuration * 1000),
            processingTimeMs: measuredLatencyMs
        )
        try? deps.store.save(record)

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
        if let app = deps.appDetector.frontmostApp(),
           let appMode = settings.appMapping[app.bundleIdentifier] {
            return appMode
        }
        return settings.contextMode
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
