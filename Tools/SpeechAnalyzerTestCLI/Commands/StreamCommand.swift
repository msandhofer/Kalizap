import AVFoundation
import CoreMedia
import Foundation
import Speech
import STTTestCommon

// MARK: - Stream Command (real-time streaming from file)

@available(macOS 26, *)
func runStreamMode(args: StreamArgs) async throws {
    let locale = resolveLocale(args.locale)
    let isJSON = args.json

    if !isJSON {
        print("=== SpeechAnalyzerTestCLI — Stream Mode (Realtime) ===")
        print("Audio:   \(args.audioPath)")
        print("Locale:  \(locale.identifier)")
        print("")
    }

    // 1. Setup
    let setupStart = ContinuousClock.now
    let transcriber = createTranscriber(locale: locale, preset: .progressiveTranscription)
    try await ensureLocaleInstalled(locale: locale, transcriber: transcriber)
    let setupTime = ContinuousClock.now - setupStart

    // 2. Load audio file and get duration
    let audioURL = URL(fileURLWithPath: args.audioPath)
    let sourceFile = try AVAudioFile(forReading: audioURL)
    let audioDuration = Double(sourceFile.length) / sourceFile.processingFormat.sampleRate

    // 3. Prepare the analyzer input format (16kHz mono Int16 — required by SpeechAnalyzer)
    let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    // Convert entire file to Int16 samples for chunked feeding
    guard let converter = AVAudioConverter(from: sourceFile.processingFormat, to: audioFormat) else {
        throw NSError(domain: "StreamCommand", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
    }
    let frameCount = AVAudioFrameCount(Double(sourceFile.length) * 16000.0 / sourceFile.processingFormat.sampleRate)
    guard let fullBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
        throw NSError(domain: "StreamCommand", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create output buffer"])
    }
    var convError: NSError?
    converter.convert(to: fullBuffer, error: &convError) { _, outStatus in
        let inputFrameCount = min(sourceFile.length - sourceFile.framePosition, Int64(4096))
        guard inputFrameCount > 0 else {
            outStatus.pointee = .endOfStream
            return nil
        }
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFile.processingFormat,
            frameCapacity: AVAudioFrameCount(inputFrameCount)
        ) else {
            outStatus.pointee = .endOfStream
            return nil
        }
        do {
            try sourceFile.read(into: inputBuffer)
            outStatus.pointee = .haveData
            return inputBuffer
        } catch {
            outStatus.pointee = .endOfStream
            return nil
        }
    }
    if let convError { throw convError }

    let totalSamples = Int(fullBuffer.frameLength)

    if !isJSON {
        print("Audio geladen: \(totalSamples) samples (\(String(format: "%.1f", audioDuration))s)")
        print("Setup: \(formatMs(setupTime))")
        print("")
    }

    // 4. Run real-time streaming with two concurrent tasks
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let streamStart = ContinuousClock.now

    // Shared state for timing
    let state = StreamState()

    // Task 2: Result consumer — started BEFORE feeding audio
    async let resultTask: Void = consumeResults(
        transcriber: transcriber,
        state: state,
        streamStart: streamStart,
        verbose: !isJSON
    )

    // Task 1: Audio feeder — feeds chunks at real-time rate
    let chunkDurationMs = 100  // 100ms chunks
    let samplesPerChunk = 16000 * chunkDurationMs / 1000  // 1600 samples

    let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

    // Start analyzer consuming the input stream
    async let analyzerTask: CMTime? = analyzer.analyzeSequence(inputStream)

    var cursor = 0
    var chunkIndex = 0
    let int16Data = fullBuffer.int16ChannelData!

    while cursor < totalSamples {
        let end = min(cursor + samplesPerChunk, totalSamples)
        let chunkLength = end - cursor

        // Create AVAudioPCMBuffer from chunk (Int16)
        let chunkFrameCount = AVAudioFrameCount(chunkLength)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: chunkFrameCount) else {
            throw NSError(domain: "StreamCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio buffer"])
        }
        buffer.frameLength = chunkFrameCount
        buffer.int16ChannelData![0].update(from: int16Data[0].advanced(by: cursor), count: chunkLength)

        let input = AnalyzerInput(buffer: buffer)
        continuation.yield(input)

        cursor = end
        chunkIndex += 1

        // Real-time pacing: sleep 100ms between chunks
        if cursor < totalSamples {
            try await Task.sleep(for: .milliseconds(chunkDurationMs))
        }
    }

    // Signal "stop" — record the timestamp
    let stopTimestamp = ContinuousClock.now
    await state.setStopTimestamp(stopTimestamp)

    if !isJSON {
        let feedingMs = durationToMs(stopTimestamp - streamStart)
        print("\n--- Audio-Feeding abgeschlossen: \(chunkIndex) Chunks in \(feedingMs)ms ---")
    }

    // Finalize: tell analyzer no more audio is coming
    continuation.finish()
    if let lastTime = try await analyzerTask {
        try await analyzer.finalizeAndFinish(through: lastTime)
    } else {
        await analyzer.cancelAndFinishNow()
    }

    // Wait for result consumer to finish
    try await resultTask

    let totalTime = ContinuousClock.now - streamStart

    // 5. Collect results
    let finalText = await state.finalText
    let volatileCount = await state.volatileCount
    let firstResultMs = await state.firstResultMs
    let streamLatencyMs = await state.streamLatencyMs

    // 6. WER
    let fm = FileManager.default
    let baseName = (args.audioPath as NSString).deletingPathExtension
    let expectedTxt = baseName + ".txt"
    let expectedLong = baseName + ".expected.txt"
    let expectedPath = fm.fileExists(atPath: expectedTxt) ? expectedTxt : expectedLong
    let expected: String? = fm.fileExists(atPath: expectedPath)
        ? try? String(contentsOfFile: expectedPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        : nil

    let wer: Double? = expected.flatMap { exp in
        guard !exp.isEmpty else { return nil }
        return WERScoring.calculate(hypothesis: finalText, reference: exp).wer
    }

    // 7. Output
    if isJSON {
        let output = SpeechAnalyzerStreamResult(
            file: (args.audioPath as NSString).lastPathComponent,
            locale: locale.identifier,
            wer: wer,
            firstResultMs: firstResultMs,
            streamLatencyMs: streamLatencyMs,
            volatileCount: volatileCount,
            audioDurationSeconds: audioDuration,
            totalMs: Int(durationToMs(totalTime)),
            text: finalText,
            expected: expected
        )
        print(try TestResultJSON.encode(output))
    } else {
        print("")
        print("=== Ergebnis ===")
        print("Text:              \(finalText.prefix(80))\(finalText.count > 80 ? "..." : "")")
        if let expected, !expected.isEmpty {
            print("Soll:              \(expected.prefix(80))\(expected.count > 80 ? "..." : "")")
        }
        if let wer { print("WER:               \(String(format: "%.1f", wer * 100))%") }
        print("Erstes Result:     \(firstResultMs)ms")
        print("Stream-Latenz:     \(streamLatencyMs)ms (Stop → finales Result)")
        print("Volatile Results:  \(volatileCount)")
        print("Audio-Dauer:       \(String(format: "%.1f", audioDuration))s")
        print("Gesamt:            \(formatMs(totalTime))")
    }
}

// MARK: - Stream State (actor for thread-safe mutation)

@available(macOS 26, *)
actor StreamState {
    var finalText = ""
    var volatileCount = 0
    var firstResultMs = 0
    var streamLatencyMs = 0

    private var stopTimestamp: ContinuousClock.Instant?
    private var firstResultRecorded = false

    func setStopTimestamp(_ ts: ContinuousClock.Instant) {
        stopTimestamp = ts
    }

    func recordResult(text: String, isFinal: Bool, timestamp: ContinuousClock.Instant, streamStart: ContinuousClock.Instant) {
        if !firstResultRecorded {
            firstResultMs = Int(durationToMs(timestamp - streamStart))
            firstResultRecorded = true
        }

        if isFinal {
            // Append final text
            if finalText.isEmpty {
                finalText = text
            } else {
                finalText += " " + text
            }
        } else {
            volatileCount += 1
        }

        // If stop was signaled and this is a result after stop, record latency
        if let stop = stopTimestamp, isFinal {
            streamLatencyMs = Int(durationToMs(timestamp - stop))
        }
    }
}

// MARK: - Result Consumer

@available(macOS 26, *)
func consumeResults(
    transcriber: SpeechTranscriber,
    state: StreamState,
    streamStart: ContinuousClock.Instant,
    verbose: Bool
) async throws {
    for try await result in transcriber.results {
        let timestamp = ContinuousClock.now
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isFinal = result.isFinal

        await state.recordResult(
            text: text,
            isFinal: isFinal,
            timestamp: timestamp,
            streamStart: streamStart
        )

        if verbose {
            let elapsed = durationToMs(timestamp - streamStart)
            let kind = isFinal ? "FINAL" : "volatile"
            print("  [\(elapsed)ms] \(kind): \(text.prefix(60))\(text.count > 60 ? "..." : "")")
        }
    }
}
