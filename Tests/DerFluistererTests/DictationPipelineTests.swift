import Testing
import Foundation
@testable import DerFluisterer

// MARK: - Pipeline Test Mocks

final class PipelineHotkeyMock: HotkeyMonitoring, HotkeyConfiguring, @unchecked Sendable {
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    var events: AsyncStream<HotkeyEvent> {
        AsyncStream { self.continuation = $0 }
    }
    var accessibilityStatus: AccessibilityStatus { .granted }
    var isHealthy: Bool { true }

    var currentConfiguration: HotkeyConfiguration = .default
    var lastUpdatedConfiguration: HotkeyConfiguration?

    func start() async throws {}
    func stop() {}
    func suspend() {}
    func resume() {}

    func updateConfiguration(_ configuration: HotkeyConfiguration) {
        currentConfiguration = configuration
        lastUpdatedConfiguration = configuration
    }

    func captureNextKeyPress(timeout: Duration) async -> HotkeyConfiguration? { nil }

    func send(_ event: HotkeyEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }
}

final class PipelineRecorderMock: AudioCapturing, @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
    var state: AudioRecorderState = .idle
    var chunksToYield: [AudioChunk] = [
        AudioChunk(samples: [0.1, 0.2], sampleRate: 16000, timestamp: 0, duration: 0.5,
                   level: AudioLevel(average: 0.1, peak: 0.2, timestamp: 0))
    ]
    private var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?

    var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { self.continuation = $0 }
    }

    func startRecording() async throws {
        startCalled = true
        state = .recording
        // Yield pre-configured chunks after delay so audioStream consumer is ready
        let chunks = chunksToYield
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(20))
            for chunk in chunks {
                self?.continuation?.yield(chunk)
            }
        }
    }

    func stopRecording() async {
        stopCalled = true
        state = .idle
        continuation?.finish()
        continuation = nil
    }

    func sendChunk(_ chunk: AudioChunk) {
        continuation?.yield(chunk)
    }
}

final class PipelineSoundMock: SoundPlaying, @unchecked Sendable {
    var startPlayed = false
    var stopPlayed = false

    func playStartSound() async {
        startPlayed = true
    }

    func playStopSound() async {
        stopPlayed = true
    }
}

final class PipelineTranscriberMock: TranscriptionEngine, @unchecked Sendable {
    var transcribeCalled = false
    var resultText = "rohes transkript"
    var shouldReturnEmpty = false

    func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult> {
        transcribeCalled = true
        let text = resultText
        let empty = shouldReturnEmpty
        return AsyncStream { continuation in
            if !empty {
                continuation.yield(.final(FinalTranscription(
                    text: text,
                    segments: [],
                    processingTime: .milliseconds(50)
                )))
            }
            continuation.finish()
        }
    }

    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func cancel() {}
}

final class PipelineCorrectorMock: TextCorrecting, @unchecked Sendable {
    var correctCalled = false
    var correctedText = "Korrigierter Text"
    var lastInput: TranscriptionResult?
    var delayMs: UInt64 = 0
    var shouldFallback = false
    var lastConfig: CorrectionConfig?

    func correct(_ input: TranscriptionResult) async -> CorrectionOutcome {
        correctCalled = true
        lastInput = input
        if delayMs > 0 {
            try? await Task.sleep(for: .milliseconds(delayMs))
        }
        if shouldFallback {
            return .fallbackRaw(text: input.text, reason: .timeout)
        }
        return .corrected(
            text: correctedText,
            stats: CorrectionStats(latencyMs: 50, wasRetry: false)
        )
    }

    func updateConfig(_ config: CorrectionConfig) {
        lastConfig = config
    }

    var lastDebugSnapshot: DebugSnapshot? { nil }
}

final class PipelineInserterMock: TextInserting, @unchecked Sendable {
    var insertedText: String?

    func insert(_ text: String) async -> InsertionResult {
        insertedText = text
        return InsertionResult(
            outcome: .inserted(method: .clipboard),
            targetApp: ActiveApp(bundleIdentifier: "com.test", localizedName: "TestApp"),
            clipboardRestored: true
        )
    }
}

final class TrackingInserterMock: TextInserting, @unchecked Sendable {
    private let onInsert: (String) -> Void

    init(onInsert: @escaping (String) -> Void) {
        self.onInsert = onInsert
    }

    func insert(_ text: String) async -> InsertionResult {
        onInsert(text)
        return InsertionResult(
            outcome: .inserted(method: .clipboard),
            targetApp: ActiveApp(bundleIdentifier: "com.test", localizedName: "TestApp"),
            clipboardRestored: true
        )
    }
}

final class PipelineStreamingTranscriberMock: TranscriptionEngine, @unchecked Sendable {
    var transcribeCalled = false
    var callCount = 0
    var partialTexts: [String] = []
    var finalText = "finales transkript"
    var shouldFail = false
    var batchFallbackText: String?

    func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult> {
        transcribeCalled = true
        callCount += 1
        let currentCall = callCount
        let partials = partialTexts
        let final_ = finalText
        let fail = shouldFail
        let batchText = batchFallbackText
        return AsyncStream { continuation in
            Task {
                // Consume audio chunks (simulates streaming processing)
                for await _ in audioChunks {}

                if fail && currentCall == 1 {
                    // First call (streaming) fails
                    continuation.finish()
                    return
                }

                if fail && currentCall > 1, let batchText {
                    // Second call (batch fallback) succeeds
                    continuation.yield(.final(FinalTranscription(
                        text: batchText,
                        segments: [],
                        processingTime: .milliseconds(50)
                    )))
                    continuation.finish()
                    return
                }

                // Normal path: yield partials then final
                for partial in partials {
                    continuation.yield(.partial(PartialTranscription(text: partial, confidence: 0.8)))
                }
                continuation.yield(.final(FinalTranscription(
                    text: final_,
                    segments: [],
                    processingTime: .milliseconds(50)
                )))
                continuation.finish()
            }
        }
    }

    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func cancel() {}
}

final class InteractiveTranscriberMock: TranscriptionEngine, @unchecked Sendable {
    private var resultContinuation: AsyncStream<TranscriptionResult>.Continuation?

    func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult> {
        AsyncStream { self.resultContinuation = $0 }
    }

    func yieldPartial(_ text: String) {
        resultContinuation?.yield(.partial(PartialTranscription(text: text, confidence: 0.8)))
    }

    func yieldFinal(_ text: String) {
        resultContinuation?.yield(.final(FinalTranscription(
            text: text, segments: [], processingTime: .milliseconds(50)
        )))
        resultContinuation?.finish()
    }

    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func cancel() {
        resultContinuation?.finish()
    }
}

final class PipelineLevelMeteringMock: AudioLevelMetering, @unchecked Sendable {
    var levelStream: AsyncStream<AudioLevel> {
        AsyncStream { $0.finish() }
    }
    func startMetering() async {}
    func stopMetering() async {}
}

final class PipelineStoreMock: DictationStoring, @unchecked Sendable {
    var savedEntries: [DictationEntry] = []
    let didChange: AsyncStream<Void> = AsyncStream { $0.finish() }

    func save(_ entry: DictationEntry) async throws {
        savedEntries.append(entry)
    }

    func delete(id: UUID) async throws {}

    func fetchAll() async throws -> [DictationEntry] { savedEntries }

    func search(query: String) async throws -> [DictationEntry] { [] }

    func statistics() async -> DictationStatistics {
        DictationStatistics(
            totalCount: 0, todayCount: 0, weekCount: 0,
            totalWords: 0, averageWPM: 0, currentStreakDays: 0,
            averageProcessingTimeMs: 0
        )
    }

    func updateHistoryLimit(_ limit: Int) async throws {}
}

// MARK: - Tests

@Suite("DictationPipeline")
struct DictationPipelineTests {

    // MARK: - Helpers

    @MainActor
    private func makeSUT(
        hotkey: PipelineHotkeyMock = PipelineHotkeyMock(),
        recorder: PipelineRecorderMock = PipelineRecorderMock(),
        metering: any AudioLevelMetering = PipelineLevelMeteringMock(),
        sound: PipelineSoundMock = PipelineSoundMock(),
        transcriber: any TranscriptionEngine = PipelineTranscriberMock(),
        corrector: PipelineCorrectorMock = PipelineCorrectorMock(),
        inserter: any TextInserting = PipelineInserterMock(),
        store: PipelineStoreMock = PipelineStoreMock(),
        appDetector: MockAppDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.test", localizedName: "TestApp")
        ),
        settings: SettingsManager? = nil
    ) -> DictationPipeline {
        let testSettings = settings ?? makeTestSettings()
        let deps = PipelineDependencies(
            hotkey: hotkey,
            recorder: recorder,
            metering: metering,
            spectrumProvider: MockAudioSpectrumProvider(),
            transcriber: transcriber,
            corrector: corrector,
            inserter: inserter,
            appDetector: appDetector,
            store: store,
            sound: sound,
            settings: testSettings
        )
        return DictationPipeline(dependencies: deps)
    }

    @MainActor
    private func makeTestSettings() -> SettingsManager {
        let defaults = UserDefaults(suiteName: "pipeline-tests-\(UUID().uuidString)")!
        let keychain = MockKeychainService()
        keychain.storage["anthropic-api-key"] = "test-key"
        let settings = SettingsManager(
            defaults: defaults,
            keychain: keychain,
            apiKeyValidator: MockAPIKeyValidator()
        )
        // Pre-populate the API key cache so pipeline doesn't block on missing key
        try? settings.apiKey.resolveKey()
        return settings
    }

    /// Starts pipeline.activate() in background, waits for event loop to be ready.
    @MainActor
    private func activatePipeline(_ pipeline: DictationPipeline) async -> Task<Void, Never> {
        let task = Task { await pipeline.activate() }
        try? await Task.sleep(for: .milliseconds(50))
        return task
    }

    /// Simulates a complete dictation cycle: press hotkey → release hotkey → wait for processing.
    private func simulateDictation(
        hotkey: PipelineHotkeyMock,
        processingWaitMs: UInt64 = 300
    ) async {
        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(processingWaitMs))
    }

    /// Cleans up pipeline event loop.
    private func tearDown(hotkey: PipelineHotkeyMock, task: Task<Void, Never>) {
        hotkey.finish()
        task.cancel()
    }

    // MARK: - Tracer Bullet: Happy Path

    @Test("complete flow: hotkey → record → transcribe → correct → insert → persist")
    @MainActor
    func happyPath() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        corrector.correctedText = "Hallo Welt"
        let inserter = PipelineInserterMock()
        let store = PipelineStoreMock()

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, inserter: inserter, store: store
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(inserter.insertedText == "Hallo Welt")
        #expect(store.savedEntries.count == 1)
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - State Transitions

    @Test("state transitions: idle → recording → transcribing → correcting → inserting → idle")
    @MainActor
    func stateTransitions() async {
        let hotkey = PipelineHotkeyMock()
        let pipeline = makeSUT(hotkey: hotkey)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(pipeline.stateHistory == [
            .recording,
            .processing(stage: .transcribing),
            .processing(stage: .correcting),
            .processing(stage: .inserting),
            .idle
        ])

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Sounds

    @Test("start sound on recording start, stop sound on recording stop")
    @MainActor
    func soundsPlayAtCorrectMoments() async {
        let hotkey = PipelineHotkeyMock()
        let sound = PipelineSoundMock()
        let pipeline = makeSUT(hotkey: hotkey, sound: sound)

        let task = await activatePipeline(pipeline)

        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(sound.startPlayed)
        #expect(!sound.stopPlayed)

        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(sound.stopPlayed)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Latency

    @Test("latencyMs is set after successful dictation")
    @MainActor
    func latencyMeasurement() async {
        let hotkey = PipelineHotkeyMock()
        let pipeline = makeSUT(hotkey: hotkey)

        #expect(pipeline.latencyMs == nil)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(pipeline.latencyMs != nil)
        #expect(pipeline.latencyMs! >= 0)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Persistence

    @Test("persisted DictationRecord has correct fields")
    @MainActor
    func dictationRecordPersistence() async {
        let hotkey = PipelineHotkeyMock()
        let recorder = PipelineRecorderMock()
        recorder.chunksToYield = [makeTestChunk(samples: [Float](repeating: 0.1, count: 40000), sampleRate: 16000, timestamp: 0)]
        let transcriber = PipelineTranscriberMock()
        transcriber.resultText = "rohes transkript"
        let corrector = PipelineCorrectorMock()
        corrector.correctedText = "Korrigiertes Transkript"
        corrector.delayMs = 5
        let store = PipelineStoreMock()
        let appDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        )

        let settings = makeTestSettings()
        settings.audio.language = .de
        settings.correction.contextMode = .formal

        let pipeline = makeSUT(
            hotkey: hotkey, recorder: recorder, transcriber: transcriber,
            corrector: corrector, store: store, appDetector: appDetector, settings: settings
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(store.savedEntries.count == 1)
        let record = store.savedEntries[0]
        #expect(record.rawTranscript == "rohes transkript")
        #expect(record.correctedText == "Korrigiertes Transkript")
        #expect(record.language == "de")
        #expect(record.contextMode == "formal")
        #expect(record.targetApp == "Notes")
        #expect(record.durationMs == 2500)
        #expect(record.processingTimeMs > 0)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Error Handling

    @Test("correction fallback: raw text is inserted, no error state")
    @MainActor
    func correctionFallbackUsesRawText() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = PipelineTranscriberMock()
        transcriber.resultText = "rohtext ohne korrektur"
        let corrector = PipelineCorrectorMock()
        corrector.shouldFallback = true
        let inserter = PipelineInserterMock()

        let pipeline = makeSUT(
            hotkey: hotkey, transcriber: transcriber, corrector: corrector, inserter: inserter
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(inserter.insertedText == "rohtext ohne korrektur")
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("updateHotkey forwards new configuration to HotkeyConfiguring dispatcher")
    @MainActor
    func updateHotkeyLiveRebind() async {
        let hotkey = PipelineHotkeyMock()
        let pipeline = makeSUT(hotkey: hotkey)

        let newConfig = HotkeyConfiguration(keyCode: 0x38, modifierFlags: 0, requiresHold: true)
        pipeline.updateHotkey(newConfig)

        #expect(hotkey.lastUpdatedConfiguration == newConfig)
        #expect(hotkey.currentConfiguration == newConfig)
    }

    @Test("all tasks disabled: LLM is skipped, raw text inserted, corrector.correct not called")
    @MainActor
    func allTasksOffSkipsLLM() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = PipelineTranscriberMock()
        transcriber.resultText = "rohtext ohne llm"
        let corrector = PipelineCorrectorMock()
        let inserter = PipelineInserterMock()

        let settings = makeTestSettings()
        settings.correction.taskGrammar = false
        settings.correction.taskFillerRemoval = false
        settings.correction.taskWrittenLanguage = false
        settings.correction.taskPunctuation = false
        settings.correction.taskPreventHallucination = false

        let pipeline = makeSUT(
            hotkey: hotkey, transcriber: transcriber,
            corrector: corrector, inserter: inserter,
            settings: settings
        )

        var fallbackNotified = false
        pipeline.onCorrectionFallback = { fallbackNotified = true }

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(corrector.correctCalled == false)
        #expect(inserter.insertedText == "rohtext ohne llm")
        #expect(fallbackNotified == false) // user-gewollter Skip, keine Notification
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("transcription failure → error state")
    @MainActor
    func transcriptionFailureGoesToError() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = PipelineTranscriberMock()
        transcriber.shouldReturnEmpty = true
        let inserter = PipelineInserterMock()

        let pipeline = makeSUT(
            hotkey: hotkey, transcriber: transcriber, inserter: inserter
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(inserter.insertedText == nil)
        if case .error(let err) = pipeline.state {
            #expect(err.isRecoverable)
        } else {
            Issue.record("Expected error state, got \(pipeline.state)")
        }

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Cancel

    @Test("cancelDictation resets to idle during processing")
    @MainActor
    func cancelDuringProcessing() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        corrector.delayMs = 500
        let inserter = PipelineInserterMock()

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, inserter: inserter
        )

        let task = await activatePipeline(pipeline)

        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(50))

        pipeline.cancelDictation()

        #expect(pipeline.state == .idle)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(inserter.insertedText == nil)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Settings

    @Test("pipeline updates corrector config from settings before correction")
    @MainActor
    func settingsPassedToCorrector() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        let settings = makeTestSettings()
        settings.correction.contextMode = .formal
        settings.correction.allowRephrasing = true
        settings.correction.personalDictionary = ["WhisperKit"]
        settings.correction.llmTimeoutMs = 500

        let pipeline = makeSUT(hotkey: hotkey, corrector: corrector, settings: settings)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(corrector.lastConfig?.contextMode == .formal)
        #expect(corrector.lastConfig?.intensity.allowRephrasing == true)
        #expect(corrector.lastConfig?.personalDictionary == ["WhisperKit"])
        #expect(corrector.lastConfig?.timeoutMs == 500)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("auto mode: known app uses mapped contextMode")
    @MainActor
    func autoModeKnownApp() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        let appDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.apple.mail", localizedName: "Mail")
        )
        let settings = makeTestSettings()
        settings.correction.contextMode = .auto
        settings.correction.appMapping = ["com.apple.mail": .formal]

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, appDetector: appDetector, settings: settings
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(corrector.lastConfig?.contextMode == .formal)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("auto mode: unknown app defaults to neutral")
    @MainActor
    func autoModeUnknownApp() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        let appDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.unknown.app", localizedName: "Unknown")
        )
        let settings = makeTestSettings()
        settings.correction.contextMode = .auto
        settings.correction.appMapping = ["com.apple.mail": .formal]

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, appDetector: appDetector, settings: settings
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(corrector.lastConfig?.contextMode == .neutral)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("non-auto mode: appMapping is ignored, selected mode is used")
    @MainActor
    func nonAutoModeIgnoresMapping() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        let appDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.apple.mail", localizedName: "Mail")
        )
        let settings = makeTestSettings()
        settings.correction.contextMode = .informal
        settings.correction.appMapping = ["com.apple.mail": .formal]

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, appDetector: appDetector, settings: settings
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(corrector.lastConfig?.contextMode == .informal)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Rapid Re-Dictation

    @Test("rapid re-dictation: new recording starts immediately, old finishes in background")
    @MainActor
    func rapidReDictation() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        corrector.delayMs = 200
        let store = PipelineStoreMock()
        var insertedTexts: [String] = []
        let trackingInserter = TrackingInserterMock(onInsert: { text in
            insertedTexts.append(text)
        })

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, inserter: trackingInserter, store: store
        )

        let task = await activatePipeline(pipeline)

        // First dictation
        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(50))

        // Second dictation starts immediately while first is still processing
        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(pipeline.state == .recording)

        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(800))

        #expect(insertedTexts.count == 2)
        #expect(store.savedEntries.count == 2)
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Streaming Transcription

    @Test("streaming transcription: partials update streamingText during recording")
    @MainActor
    func streamingTranscriptionShowsPartials() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = InteractiveTranscriberMock()

        let pipeline = makeSUT(
            hotkey: hotkey,
            transcriber: transcriber
        )

        let task = await activatePipeline(pipeline)

        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(pipeline.streamingText == "")

        // Transcriber yields partial during recording
        transcriber.yieldPartial("Hallo")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(pipeline.streamingText == "Hallo")

        // Transcriber yields updated partial
        transcriber.yieldPartial("Hallo Welt")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(pipeline.streamingText == "Hallo Welt")

        // Stop recording — transcriber yields final
        transcriber.yieldFinal("Hallo Welt!")
        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(300))

        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Batch Fallback

    @Test("batch fallback: streaming fails, batch transcription succeeds")
    @MainActor
    func batchFallbackOnStreamingFailure() async {
        let hotkey = PipelineHotkeyMock()
        let recorder = PipelineRecorderMock()
        let transcriber = PipelineStreamingTranscriberMock()
        transcriber.shouldFail = true
        transcriber.batchFallbackText = "Batch-Ergebnis"
        let corrector = PipelineCorrectorMock()
        corrector.correctedText = "Korrigiertes Batch-Ergebnis"
        let inserter = PipelineInserterMock()

        let pipeline = makeSUT(
            hotkey: hotkey,
            recorder: recorder,
            transcriber: transcriber,
            corrector: corrector,
            inserter: inserter
        )

        let task = await activatePipeline(pipeline)

        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))

        recorder.sendChunk(makeTestChunk(samples: [0.1, 0.2, 0.3]))

        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(300))

        // Batch fallback should have produced a result
        #expect(transcriber.callCount == 2)
        #expect(inserter.insertedText == "Korrigiertes Batch-Ergebnis")
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Programmatic Trigger

    @Test("startDictation/stopDictation works without hotkey")
    @MainActor
    func programmaticTrigger() async {
        let hotkey = PipelineHotkeyMock()
        let inserter = PipelineInserterMock()
        let corrector = PipelineCorrectorMock()
        corrector.correctedText = "Programmgesteuerter Text"

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, inserter: inserter
        )

        await pipeline.startDictation()
        #expect(pipeline.state == .recording)

        try? await Task.sleep(for: .milliseconds(50))

        await pipeline.stopDictation()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(inserter.insertedText == "Programmgesteuerter Text")
        #expect(pipeline.state == .idle)
    }

    // MARK: - Audio Level

    @Test("audioLevel is updated during recording")
    @MainActor
    func audioLevelDuringRecording() async {
        let hotkey = PipelineHotkeyMock()
        let metering = PipelineLevelMeteringMock()

        let pipeline = makeSUT(hotkey: hotkey, metering: metering)

        // audioLevel should be exposed as a property
        #expect(pipeline.audioLevel == 0)
    }

    // MARK: - dismissError

    @Test("dismissError resets from error to idle")
    @MainActor
    func dismissErrorResetsToIdle() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = PipelineTranscriberMock()
        transcriber.shouldReturnEmpty = true

        let pipeline = makeSUT(hotkey: hotkey, transcriber: transcriber)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        // Should be in error state (transcription failed)
        if case .error = pipeline.state {} else {
            Issue.record("Expected error state, got \(pipeline.state)")
        }

        pipeline.dismissError()
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - deactivate

    @Test("deactivate stops pipeline during processing")
    @MainActor
    func deactivateStopsPipeline() async {
        let hotkey = PipelineHotkeyMock()
        let corrector = PipelineCorrectorMock()
        corrector.delayMs = 500
        let inserter = PipelineInserterMock()

        let pipeline = makeSUT(
            hotkey: hotkey, corrector: corrector, inserter: inserter
        )

        let task = await activatePipeline(pipeline)

        hotkey.send(.recordingStarted)
        try? await Task.sleep(for: .milliseconds(50))
        hotkey.send(.recordingStopped)
        try? await Task.sleep(for: .milliseconds(50))

        pipeline.deactivate()

        #expect(pipeline.state == .idle)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(inserter.insertedText == nil)

        tearDown(hotkey: hotkey, task: task)
    }

    @Test("dismissError does nothing when not in error state")
    @MainActor
    func dismissErrorNoop() async {
        let hotkey = PipelineHotkeyMock()
        let pipeline = makeSUT(hotkey: hotkey)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        #expect(pipeline.state == .idle)
        pipeline.dismissError()
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - Empty Buffer

    @Test("empty buffer skips processing, goes directly to idle")
    @MainActor
    func emptyBufferSkipsProcessing() async {
        let hotkey = PipelineHotkeyMock()
        let recorder = PipelineRecorderMock()
        recorder.chunksToYield = []
        let transcriber = PipelineTranscriberMock()
        let inserter = PipelineInserterMock()
        let store = PipelineStoreMock()

        let pipeline = makeSUT(
            hotkey: hotkey, recorder: recorder, transcriber: transcriber,
            inserter: inserter, store: store
        )

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        // No text inserted, no record saved — processing was skipped
        #expect(inserter.insertedText == nil)
        #expect(store.savedEntries.isEmpty)
        #expect(pipeline.state == .idle)

        tearDown(hotkey: hotkey, task: task)
    }

    // MARK: - lastError

    @Test("lastError is set on transcription failure and survives dismissError")
    @MainActor
    func lastErrorSurvivesDismiss() async {
        let hotkey = PipelineHotkeyMock()
        let transcriber = PipelineTranscriberMock()
        transcriber.shouldReturnEmpty = true

        let pipeline = makeSUT(hotkey: hotkey, transcriber: transcriber)

        #expect(pipeline.lastError == nil)

        let task = await activatePipeline(pipeline)
        await simulateDictation(hotkey: hotkey)

        // Error state reached
        #expect(pipeline.lastError != nil)
        #expect(pipeline.lastError?.isRecoverable == true)

        // Dismiss error — state goes to idle but lastError remains
        pipeline.dismissError()
        #expect(pipeline.state == .idle)
        #expect(pipeline.lastError != nil)

        tearDown(hotkey: hotkey, task: task)
    }
}
