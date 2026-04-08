import Foundation
import Qwen3ASR
import SpeechVAD
import STTTestCommon

// MARK: - Stream-File Mode

/// Simulates streaming on an audio file: feeds audio chunk-wise through VAD + ASR.
/// Deterministic — no timers, no mic, same input always produces same output.
func runStreamFileMode(args: StreamFileArgs) async throws {
    let isJSON = args.json

    if !isJSON {
        print("=== SpeechSwiftTestCLI — Stream-File Mode ===")
        print("Audio:      \(args.audioPath)")
        print("Sprache:    \(args.language)")
        print("minSegment: \(args.minSegment)s")
        print("maxSegment: \(args.maxSegment)s")
        print("minSilence: \(args.minSilence)s")
        print("")
    }

    // 1. Load audio
    let (samples, audioDuration) = try AudioLoader.loadSamples(from: args.audioPath)
    if !isJSON {
        print("Audio geladen: \(samples.count) samples (\(String(format: "%.1f", audioDuration))s)")
    }

    // 2. Load models
    let (asrModel, _) = try await loadASRModel()
    let (vadModel, _) = try await loadVADModel()

    // 3. Run stream simulation
    let result = try simulateStream(
        samples: samples,
        audioDuration: audioDuration,
        audioPath: args.audioPath,
        asrModel: asrModel,
        vadModel: vadModel,
        language: args.language,
        minSegment: args.minSegment,
        maxSegment: args.maxSegment,
        minSilence: args.minSilence,
        verbose: !isJSON
    )

    // 4. Load expected text for WER
    let fm = FileManager.default
    let baseName = URL(fileURLWithPath: args.audioPath).deletingPathExtension().path
    let expectedTxt = baseName + ".txt"
    let expectedLong = baseName + ".expected.txt"
    let expectedPath = fm.fileExists(atPath: expectedTxt) ? expectedTxt : expectedLong
    let expected: String? = fm.fileExists(atPath: expectedPath)
        ? try? String(contentsOfFile: expectedPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        : nil

    let werResult: Double? = expected.map { exp in
        WERScoring.calculate(hypothesis: result.text, reference: exp).wer
    }

    // 5. Build output
    let streamFileResult = StreamFileResult(
        file: URL(fileURLWithPath: args.audioPath).lastPathComponent,
        engine: "qwen3-asr",
        params: StreamFileParams(
            minSegment: Double(args.minSegment),
            maxSegment: Double(args.maxSegment),
            minSilence: args.minSilence
        ),
        segments: result.segmentCount,
        wer: werResult,
        latency_after_stop_ms: result.latencyAfterStopMs,
        total_stt_ms: result.totalSttMs,
        text: result.text,
        expected: expected
    )

    if isJSON {
        print(try TestResultJSON.encode(streamFileResult))
    } else {
        print("")
        printTimingTable([
            ("Audio-Dauer", "\(String(format: "%.1f", audioDuration))s"),
            ("Segmente", "\(result.segmentCount)"),
            ("Gesamt-STT", "\(result.totalSttMs)ms"),
            ("Latenz nach Stop", "\(result.latencyAfterStopMs)ms (STT letztes Segment)"),
        ])
        print("Text: \(result.text)")
        if let expected {
            print("Soll: \(expected)")
        }
        if let werResult {
            print("WER:  \(String(format: "%.1f", werResult * 100))%")
        }
        print("\nPASS")
    }
}

// MARK: - Stream Simulation Engine

struct StreamSimulationResult {
    let text: String
    let segmentCount: Int
    let totalSttMs: Int
    let latencyAfterStopMs: Int
}

/// Core stream simulation: feeds audio chunk-wise through VAD, transcribes segments.
/// Reusable by sweep mode.
func simulateStream(
    samples: [Float],
    audioDuration: Double,
    audioPath: String,
    asrModel: Qwen3ASRModel,
    vadModel: SileroVADModel,
    language: String?,
    minSegment: Float,
    maxSegment: Float,
    minSilence: Double,
    verbose: Bool
) throws -> StreamSimulationResult {
    let vadConfig = VADConfig(
        onset: 0.5,
        offset: 0.35,
        minSpeechDuration: 0.25,
        minSilenceDuration: Float(minSilence),
        windowDuration: 0.032,
        stepRatio: 1.0
    )
    let processor = StreamingVADProcessor(model: vadModel, config: vadConfig)
    processor.reset()

    var segmentTexts: [(text: String, sttMs: Int)] = []
    var lastTranscribedEnd: Float = 0
    var pendingAudioStart: Float? = nil
    var currentSpeechStartTime: Float? = nil

    let chunkSize = 512  // 32ms at 16kHz
    var cursor = 0

    func transcribeSegment(startTime: Float, endTime: Float, label: String) {
        let context: String? = (endTime - startTime) > 1.0 ? segmentTexts.last?.text : nil
        let startIdx = max(0, Int(startTime * 16000))
        let endIdx = min(Int(endTime * 16000), samples.count)
        guard endIdx - startIdx > 1600 else { return }
        let segmentAudio = Array(samples[startIdx..<endIdx])

        let sttStart = ContinuousClock.now
        let text = asrModel.transcribe(
            audio: segmentAudio,
            sampleRate: 16000,
            language: language,
            context: context
        )
        let sttTime = ContinuousClock.now - sttStart
        let sttMs = Int(durationToMs(sttTime))

        segmentTexts.append((text: text, sttMs: sttMs))
        lastTranscribedEnd = endTime
        if verbose {
            print("  [Segment \(segmentTexts.count)] \"\(text)\" (\(label)\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s, STT: \(sttMs)ms)")
        }
    }

    // Feed chunks through VAD
    while cursor < samples.count {
        let end = min(cursor + chunkSize, samples.count)
        let chunk = Array(samples[cursor..<end])
        cursor = end

        let events = processor.process(samples: chunk)

        for event in events {
            switch event {
            case .speechStarted(let time):
                currentSpeechStartTime = time
            case .speechEnded(let segment):
                currentSpeechStartTime = nil
                let effectiveStart = max(segment.startTime, lastTranscribedEnd)
                guard segment.endTime - effectiveStart > 0.1 else { continue }

                let accumulatedStart = pendingAudioStart ?? effectiveStart

                if (segment.endTime - accumulatedStart) < minSegment {
                    if pendingAudioStart == nil {
                        pendingAudioStart = accumulatedStart
                    }
                    continue
                }

                pendingAudioStart = nil
                transcribeSegment(startTime: accumulatedStart, endTime: segment.endTime, label: "")
            }
        }

        // Force-split check
        if let speechStart = currentSpeechStartTime {
            let effectiveStart = pendingAudioStart ?? max(speechStart, lastTranscribedEnd)
            let currentTime = Float(cursor) / 16000.0
            if currentTime - effectiveStart >= maxSegment {
                pendingAudioStart = nil
                transcribeSegment(startTime: effectiveStart, endTime: currentTime, label: "force-split, ")
                currentSpeechStartTime = currentTime
            }
        }
    }

    // Flush remaining
    _ = processor.flush()
    let finalStart = pendingAudioStart ?? lastTranscribedEnd
    let totalDuration = Float(samples.count) / 16000.0
    if finalStart < totalDuration - 0.1 {
        transcribeSegment(startTime: finalStart, endTime: totalDuration, label: "flush, ")
    }

    let fullText = segmentTexts.map(\.text).joined(separator: " ")
    let totalSttMs = segmentTexts.map(\.sttMs).reduce(0, +)
    let lastSegmentSttMs = segmentTexts.last?.sttMs ?? 0

    return StreamSimulationResult(
        text: fullText,
        segmentCount: segmentTexts.count,
        totalSttMs: totalSttMs,
        latencyAfterStopMs: lastSegmentSttMs
    )
}
