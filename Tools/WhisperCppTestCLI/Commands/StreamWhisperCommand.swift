import Foundation
import Kalizap
import STTTestCommon

// MARK: - Simulation Result (internal)

struct StreamWhisperSimResult {
    let text: String
    let streamWaitMs: Int
    let totalDecodeMs: Int
    let decodeCount: Int
    let deltaSeconds: Double
    let usedPartial: Bool
}

// MARK: - Entry Point

func runStreamWhisperMode(args: StreamWhisperArgs) async throws {
    let (samples, duration) = try AudioLoader.loadSamples(from: args.audioPath)

    print("Audio:           \(args.audioPath) (\(String(format: "%.1f", duration))s)")
    print("Sprache:         \(args.language ?? "auto")")
    print("Modell:          \(args.modelName)\(args.coreml ? " (CoreML)" : "")")
    print("Fallback:        \(args.fallbackInterval)s")
    print("Tail-Intervall:  \(args.tailInterval > 0 ? "\(args.tailInterval)s" : "aus")")
    print("Partial-Accept:  \(args.partialAccept > 0 ? "\(args.partialAccept)s" : "aus")")
    print()

    let (backend, loadTime) = try await loadWhisperCppModel(
        name: args.modelName,
        language: .german,
        coreml: args.coreml
    )
    print("Modell geladen in \(loadTime.formatted())")

    let result = try await simulateWhisperStream(
        samples: samples,
        backend: backend,
        language: args.language ?? "de",
        fallbackInterval: args.fallbackInterval,
        tailInterval: args.tailInterval,
        partialAccept: args.partialAccept,
        verbose: !args.json
    )

    // Load expected text
    let baseName = (args.audioPath as NSString).deletingPathExtension
    let expectedText = (try? String(contentsOfFile: baseName + ".txt", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let wer: Double?
    if let expected = expectedText, !expected.isEmpty {
        wer = WERScoring.calculate(hypothesis: result.text, reference: expected).wer
    } else {
        wer = nil
    }

    let params = WhisperStreamParams(
        fallbackInterval: args.fallbackInterval,
        tailInterval: args.tailInterval,
        partialAccept: args.partialAccept
    )

    let output = WhisperStreamResult(
        file: (args.audioPath as NSString).lastPathComponent,
        engine: "whisper.cpp-\(args.modelName)",
        params: params,
        wer: wer,
        streamWaitMs: result.streamWaitMs,
        totalDecodeMs: result.totalDecodeMs,
        decodeCount: result.decodeCount,
        deltaSeconds: result.deltaSeconds,
        usedPartial: result.usedPartial,
        text: result.text,
        expected: expectedText
    )

    if args.json {
        print(try TestResultJSON.encode(output))
    } else {
        print()
        print("=== Ergebnis ===")
        print("Text:            \(result.text.prefix(80))...")
        if let expected = expectedText {
            print("Soll:            \(expected.prefix(80))...")
        }
        if let wer { print("WER:             \(String(format: "%.1f", wer * 100))%") }
        print("StreamWait:      \(result.streamWaitMs)ms")
        print("Total Decode:    \(result.totalDecodeMs)ms")
        print("Decode Count:    \(result.decodeCount)")
        print("Delta bei Stop:  \(String(format: "%.2f", result.deltaSeconds))s")
        print("Used Partial:    \(result.usedPartial)")
    }
}

// MARK: - Simulate WhisperTranscriptionEngine streaming

func simulateWhisperStream(
    samples: [Float],
    backend: WhisperCppBackend,
    language: String,
    fallbackInterval: Double,
    tailInterval: Double,
    partialAccept: Double,
    verbose: Bool
) async throws -> StreamWhisperSimResult {

    let sampleRate = 16000
    let pollingIntervalMs = 200
    let minSamplesForDecode = sampleRate  // 1 second

    // State
    var accumulatedText = ""
    var lastDecodedSampleCount = 0
    var lastKnownBoundaryCount = 0
    var totalDecodeMs = 0
    var decodeCount = 0

    // Track simulated time for fallback and tail logic
    var lastDecodeTickIndex = 0
    var lastTailDecodeTickIndex = 0

    // Tail-Decode Cache
    var cachedTailText = ""
    var cachedTailSampleCount = 0

    let totalSamples = samples.count
    let samplesPerTick = sampleRate * pollingIntervalMs / 1000  // 3200 at 200ms

    var simulatedSampleCount = 0
    var tickIndex = 0

    func millisSinceLastDecode() -> Double {
        Double((tickIndex - lastDecodeTickIndex) * pollingIntervalMs)
    }

    func millisSinceLastTailDecode() -> Double {
        Double((tickIndex - lastTailDecodeTickIndex) * pollingIntervalMs)
    }

    func durationMs(_ start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d / .milliseconds(1))
    }

    // Consumer loop: simulate 200ms polling ticks
    while simulatedSampleCount < totalSamples {
        tickIndex += 1
        simulatedSampleCount = min(tickIndex * samplesPerTick, totalSamples)

        guard simulatedSampleCount >= minSamplesForDecode else { continue }

        // VAD boundary detection
        let currentSamples = Array(samples.prefix(simulatedSampleCount))
        let boundaries = backend.detectSilenceBoundaries(samples: currentSamples)

        let hasNewBoundary = boundaries.count > lastKnownBoundaryCount
        let fallbackNeeded = millisSinceLastDecode() >= fallbackInterval * 1000
            && simulatedSampleCount > lastDecodedSampleCount + minSamplesForDecode

        // VAD/Fallback decode
        if hasNewBoundary || fallbackNeeded {
            let samplesToDecodeCount: Int
            if hasNewBoundary, let lastBoundary = boundaries.last {
                samplesToDecodeCount = min(Int(lastBoundary * Float(sampleRate)), simulatedSampleCount)
                lastKnownBoundaryCount = boundaries.count
            } else {
                samplesToDecodeCount = simulatedSampleCount
            }

            guard samplesToDecodeCount > lastDecodedSampleCount else { continue }

            var samplesToTranscribe = Array(samples.prefix(samplesToDecodeCount))
            AudioProcessingUtils.peakNormalize(&samplesToTranscribe)

            let decodeStart = ContinuousClock.now
            let result = try await backend.transcribe(
                samples: samplesToTranscribe,
                language: language,
                prompt: ""
            )
            let decodeMs = durationMs(decodeStart)

            accumulatedText = result.text
            lastDecodedSampleCount = samplesToDecodeCount
            lastDecodeTickIndex = tickIndex
            totalDecodeMs += decodeMs
            decodeCount += 1

            // Reset tail cache after VAD decode
            cachedTailText = ""
            cachedTailSampleCount = 0
            lastTailDecodeTickIndex = tickIndex

            if verbose {
                let kind = hasNewBoundary ? "VAD" : "Fallback"
                print("    \(kind) decode #\(decodeCount): \(samplesToDecodeCount) samples, \(decodeMs)ms, text=\(result.text.prefix(40))...")
            }
        }

        // Speculative tail decode (Ansatz C)
        if tailInterval > 0
            && lastDecodedSampleCount > 0
            && millisSinceLastTailDecode() >= tailInterval * 1000
            && simulatedSampleCount > lastDecodedSampleCount + 1600
        {
            let tailSamples = Array(samples[lastDecodedSampleCount..<simulatedSampleCount])
            var normalizedTail = tailSamples
            AudioProcessingUtils.peakNormalize(&normalizedTail)

            let decodeStart = ContinuousClock.now
            let tailResult = try await backend.transcribe(
                samples: normalizedTail,
                language: language,
                prompt: accumulatedText
            )
            let decodeMs = durationMs(decodeStart)

            cachedTailText = tailResult.text
            cachedTailSampleCount = simulatedSampleCount
            lastTailDecodeTickIndex = tickIndex
            totalDecodeMs += decodeMs
            decodeCount += 1

            if verbose {
                print("    Tail decode #\(decodeCount): \(tailSamples.count) samples, \(decodeMs)ms, tail=\(tailResult.text.prefix(40))...")
            }
        }
    }

    // --- STOP: simulate handleStop() ---

    let deltaCount = totalSamples - lastDecodedSampleCount
    let deltaSeconds = Double(deltaCount) / Double(sampleRate)

    // Check Partial-Accept (Ansatz B)
    if partialAccept > 0 && deltaSeconds < partialAccept {
        let finalText: String
        if !cachedTailText.isEmpty {
            finalText = accumulatedText + " " + cachedTailText
        } else {
            finalText = accumulatedText
        }
        if verbose {
            print("    Partial-Accept: delta=\(String(format: "%.2f", deltaSeconds))s < \(partialAccept)s, skipping final decode")
        }
        return StreamWhisperSimResult(
            text: finalText.trimmingCharacters(in: .whitespaces),
            streamWaitMs: 0,
            totalDecodeMs: totalDecodeMs,
            decodeCount: decodeCount,
            deltaSeconds: deltaSeconds,
            usedPartial: true
        )
    }

    // Check if cached tail is recent enough
    if tailInterval > 0 && !cachedTailText.isEmpty && partialAccept > 0 {
        let newSinceTail = totalSamples - cachedTailSampleCount
        let newSinceTailSeconds = Double(newSinceTail) / Double(sampleRate)
        if newSinceTailSeconds < partialAccept {
            let finalText = accumulatedText + " " + cachedTailText
            if verbose {
                print("    Tail-Cache Accept: newSinceTail=\(String(format: "%.2f", newSinceTailSeconds))s < \(partialAccept)s")
            }
            return StreamWhisperSimResult(
                text: finalText.trimmingCharacters(in: .whitespaces),
                streamWaitMs: 0,
                totalDecodeMs: totalDecodeMs,
                decodeCount: decodeCount,
                deltaSeconds: deltaSeconds,
                usedPartial: true
            )
        }
    }

    // Delta decode (standard path)
    if lastDecodedSampleCount > 0 && deltaCount >= 1600 {
        let deltaSamples = Array(samples.suffix(from: lastDecodedSampleCount))
        var normalizedDelta = deltaSamples
        AudioProcessingUtils.peakNormalize(&normalizedDelta)

        let decodeStart = ContinuousClock.now
        let delta = try await backend.transcribe(
            samples: normalizedDelta,
            language: language,
            prompt: accumulatedText
        )
        let decodeMs = durationMs(decodeStart)

        totalDecodeMs += decodeMs
        decodeCount += 1

        let finalText = accumulatedText + " " + delta.text
        if verbose {
            print("    Delta decode: \(deltaSamples.count) samples, \(decodeMs)ms, final=\(finalText.prefix(60))...")
        }
        return StreamWhisperSimResult(
            text: finalText.trimmingCharacters(in: .whitespaces),
            streamWaitMs: decodeMs,
            totalDecodeMs: totalDecodeMs,
            decodeCount: decodeCount,
            deltaSeconds: deltaSeconds,
            usedPartial: false
        )
    } else if lastDecodedSampleCount > 0 {
        // Delta too small — use accumulated text
        if verbose {
            print("    Delta too small (\(deltaCount) samples), using accumulated text")
        }
        return StreamWhisperSimResult(
            text: accumulatedText,
            streamWaitMs: 0,
            totalDecodeMs: totalDecodeMs,
            decodeCount: decodeCount,
            deltaSeconds: deltaSeconds,
            usedPartial: true
        )
    } else {
        // No VAD decode happened — full decode (short dictation)
        var normalizedSamples = samples
        AudioProcessingUtils.peakNormalize(&normalizedSamples)

        let decodeStart = ContinuousClock.now
        let result = try await backend.transcribe(
            samples: normalizedSamples,
            language: language,
            prompt: ""
        )
        let decodeMs = durationMs(decodeStart)

        if verbose {
            print("    Full decode: \(samples.count) samples, \(decodeMs)ms")
        }
        return StreamWhisperSimResult(
            text: result.text,
            streamWaitMs: decodeMs,
            totalDecodeMs: decodeMs,
            decodeCount: 1,
            deltaSeconds: Double(totalSamples) / Double(sampleRate),
            usedPartial: false
        )
    }
}
