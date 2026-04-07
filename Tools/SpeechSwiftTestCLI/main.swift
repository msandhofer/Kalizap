@preconcurrency import AVFoundation
import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - Configuration

let usage = """
Usage:
  swift run SpeechSwiftTestCLI file <audio-path> [de|en]
  swift run SpeechSwiftTestCLI live [de|en]
  swift run SpeechSwiftTestCLI stream [de|en]
  swift run SpeechSwiftTestCLI batch <directory> [de|en]
"""

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard !mode.isEmpty else {
    print(usage)
    exit(1)
}

let modelId = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"

// MARK: - Timing Helpers

func formatMs(_ duration: Duration) -> String {
    let total = duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
    return "\(total)ms"
}

func printTimingTable(_ entries: [(String, String)]) {
    let maxLabel = entries.map(\.0.count).max() ?? 0
    print("")
    print("=== Timing ===")
    for (label, value) in entries {
        let padded = label.padding(toLength: maxLabel + 2, withPad: " ", startingAt: 0)
        print("  \(padded)\(value)")
    }
    print("")
}

// MARK: - Model Loading

func loadASRModel() async throws -> (Qwen3ASRModel, Duration) {
    print("Lade Qwen3-ASR Modell (\(modelId))...")
    let start = ContinuousClock.now
    let model = try await Qwen3ASRModel.fromPretrained(
        modelId: modelId,
        progressHandler: { progress, status in
            let pct = Int(progress * 100)
            print("  \(pct)% — \(status)")
        }
    )
    let elapsed = ContinuousClock.now - start
    print("Modell geladen in \(formatMs(elapsed))")
    return (model, elapsed)
}

func loadVADModel() async throws -> (SileroVADModel, Duration) {
    print("Lade Silero VAD (CoreML)...")
    let start = ContinuousClock.now
    let vad = try await SileroVADModel.fromPretrained(engine: .coreml)
    let elapsed = ContinuousClock.now - start
    print("VAD geladen in \(formatMs(elapsed))")
    return (vad, elapsed)
}

// MARK: - File Mode

func runFileMode(path: String, language: String) async throws {
    print("=== SpeechSwiftTestCLI — File Mode ===")
    print("Audio:   \(path)")
    print("Sprache: \(language)")
    print("")

    // 1. Load audio
    let audioStart = ContinuousClock.now
    let (samples, audioDuration) = try AudioLoader.loadSamples(from: path)
    let audioLoadTime = ContinuousClock.now - audioStart
    print("Audio geladen: \(samples.count) samples (\(String(format: "%.1f", audioDuration))s)")

    // 2. Load models
    let (asrModel, modelLoadTime) = try await loadASRModel()
    let (vadModel, vadLoadTime) = try await loadVADModel()

    // 3. VAD analysis
    print("\nAnalysiere Sprachsegmente (VAD)...")
    let vadStart = ContinuousClock.now
    let segments = vadModel.detectSpeech(audio: samples, sampleRate: 16000)
    let vadAnalysisTime = ContinuousClock.now - vadStart
    let speechDuration = segments.reduce(0.0) { $0 + $1.duration }
    print("VAD: \(segments.count) Segment(e), \(String(format: "%.1f", speechDuration))s Sprache erkannt")

    // 4. Transcribe
    print("\nTranskribiere...")
    let transcribeStart = ContinuousClock.now
    let text = asrModel.transcribe(
        audio: samples,
        sampleRate: 16000,
        language: language
    )
    let transcribeTime = ContinuousClock.now - transcribeStart

    // 5. Calculate RTF
    let transcribeMs = Double(transcribeTime.components.seconds * 1000)
        + Double(transcribeTime.components.attoseconds) / 1_000_000_000_000_000.0
    let rtf = audioDuration > 0 ? transcribeMs / (audioDuration * 1000.0) : 0

    // 6. Results
    printTimingTable([
        ("Modell laden", formatMs(modelLoadTime)),
        ("VAD laden", formatMs(vadLoadTime)),
        ("Audio laden", formatMs(audioLoadTime)),
        ("Audio-Dauer", "\(String(format: "%.1f", audioDuration))s"),
        ("VAD Sprech-Dauer", "\(String(format: "%.1f", speechDuration))s"),
        ("VAD Analyse", formatMs(vadAnalysisTime)),
        ("Transkription", formatMs(transcribeTime)),
        ("RTF", String(format: "%.3f", rtf)),
    ])

    print("Text: \(text)")
    print("\nPASS")
}

// MARK: - Live Mode

func runLiveMode(language: String) async throws {
    print("=== SpeechSwiftTestCLI — Live Mode ===")
    print("Sprache: \(language)")
    print("")

    // 1. Load models (einmalig)
    let (asrModel, _) = try await loadASRModel()
    let (vadModel, _) = try await loadVADModel()

    print("\nBereit. Modelle geladen.")
    print("───────────────────────────────────")

    // 2. Recording loop
    var runNumber = 0
    while true {
        runNumber += 1
        print("\n[\(runNumber)] Drücke Enter zum Starten (oder 'q' + Enter zum Beenden)...")

        guard let input = readLine(), input != "q" else {
            print("Beende.")
            break
        }

        // Setup mic capture
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let sampleBuffer = SampleBuffer()

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("FEHLER: Audio-Converter konnte nicht erstellt werden")
            print("  Native Format: \(nativeFormat)")
            continue
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / nativeFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity + 100
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let samples = Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(convertedBuffer.frameLength)
                    )
                )
                sampleBuffer.append(samples)
            }
        }

        // Start recording
        engine.prepare()
        try engine.start()
        let recordStart = ContinuousClock.now
        print("  Aufnahme läuft... Drücke Enter zum Stoppen.")

        _ = readLine()

        // Stop recording
        _ = ContinuousClock.now - recordStart
        engine.stop()
        inputNode.removeTap(onBus: 0)

        let samples = sampleBuffer.samples
        let audioDuration = Double(samples.count) / 16000.0
        print("  Aufnahme: \(samples.count) samples (\(String(format: "%.1f", audioDuration))s)")

        guard samples.count > 1600 else {
            print("  Aufnahme zu kurz (< 0.1s), überspringe.")
            continue
        }

        // VAD analysis
        let vadStart = ContinuousClock.now
        let segments = vadModel.detectSpeech(audio: samples, sampleRate: 16000)
        let vadAnalysisTime = ContinuousClock.now - vadStart
        let speechDuration = segments.reduce(0.0) { $0 + $1.duration }

        if segments.isEmpty {
            print("  [VAD] Keine Sprache erkannt, überspringe Transkription.")
            continue
        }

        // Transcribe
        let transcribeStart = ContinuousClock.now
        let text = asrModel.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language
        )
        let transcribeTime = ContinuousClock.now - transcribeStart

        let transcribeMs = Double(transcribeTime.components.seconds * 1000)
            + Double(transcribeTime.components.attoseconds) / 1_000_000_000_000_000.0
        let rtf = audioDuration > 0 ? transcribeMs / (audioDuration * 1000.0) : 0

        // Results
        printTimingTable([
            ("Aufnahme-Dauer", "\(String(format: "%.1f", audioDuration))s"),
            ("VAD Sprech-Dauer", "\(String(format: "%.1f", speechDuration))s (\(segments.count) Segment(e))"),
            ("VAD Analyse", formatMs(vadAnalysisTime)),
            ("Transkription", formatMs(transcribeTime)),
            ("Gesamt (stop→text)", formatMs(transcribeTime + vadAnalysisTime)),
            ("RTF", String(format: "%.3f", rtf)),
        ])

        print("  Text: \(text)")
    }
}

// MARK: - Stream Mode

/// Mutable state shared between the VAD background task and the main recording loop.
/// Declared @unchecked Sendable because access is serialised by design:
/// the Task reads/writes during recording, the outer function reads after cancellation.
final class StreamState: @unchecked Sendable {
    var vadCursor: Int = 0
    var segmentTexts: [(text: String, sttDuration: Duration, startTime: Float, endTime: Float)] = []
}

func runStreamMode(language: String) async throws {
    print("=== SpeechSwiftTestCLI — Stream Mode ===")
    print("Sprache: \(language)")
    print("Real-time VAD + Segment-Transkription")
    print("")

    // 1. Load models
    let (asrModel, _) = try await loadASRModel()
    let (vadModel, _) = try await loadVADModel()
    let processor = StreamingVADProcessor(model: vadModel)

    print("\nBereit. Modelle geladen.")
    print("───────────────────────────────────")

    // 2. Recording loop
    var runNumber = 0
    while true {
        runNumber += 1
        print("\n[\(runNumber)] Drücke Enter zum Starten (oder 'q' + Enter zum Beenden)...")

        guard let input = readLine(), input != "q" else {
            print("Beende.")
            break
        }

        // Setup mic capture (same as live mode)
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let sampleBuffer = SampleBuffer()

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("FEHLER: Audio-Converter konnte nicht erstellt werden")
            continue
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / nativeFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity + 100
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil, let channelData = convertedBuffer.floatChannelData {
                let newSamples = Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(convertedBuffer.frameLength)
                    )
                )
                sampleBuffer.append(newSamples)
            }
        }

        // Start recording
        engine.prepare()
        try engine.start()
        print("  Aufnahme läuft... Drücke Enter zum Stoppen.")
        print("")

        // Streaming state (in a Sendable container so the Task can capture it)
        processor.reset()
        let state = StreamState()

        // Background VAD + transcription task
        // Use nonisolated(unsafe) to pass non-Sendable models to the task
        nonisolated(unsafe) let asrRef = asrModel
        nonisolated(unsafe) let processorRef = processor

        let vadTask = Task {
            while !Task.isCancelled {
                let newSamples = sampleBuffer.samples(from: state.vadCursor)
                if !newSamples.isEmpty {
                    state.vadCursor += newSamples.count

                    let events = processorRef.process(samples: newSamples)

                    for event in events {
                        switch event {
                        case .speechStarted(let time):
                            print("  [VAD \(String(format: "%.1f", time))s] Sprache erkannt")
                        case .speechEnded(let segment):
                            // Extract segment audio from full buffer
                            let allSamples = sampleBuffer.samples
                            let startIdx = max(0, Int(segment.startTime * 16000))
                            let endIdx = min(Int(segment.endTime * 16000), allSamples.count)
                            guard startIdx < endIdx else { continue }
                            let segmentAudio = Array(allSamples[startIdx..<endIdx])

                            // Transcribe this segment immediately
                            let sttStart = ContinuousClock.now
                            let text = asrRef.transcribe(
                                audio: segmentAudio,
                                sampleRate: 16000,
                                language: language
                            )
                            let sttTime = ContinuousClock.now - sttStart

                            state.segmentTexts.append((
                                text: text,
                                sttDuration: sttTime,
                                startTime: segment.startTime,
                                endTime: segment.endTime
                            ))

                            print("  [Segment \(state.segmentTexts.count)] \"\(text)\" (\(String(format: "%.1f", segment.startTime))-\(String(format: "%.1f", segment.endTime))s, STT: \(formatMs(sttTime)))")
                        }
                    }
                }

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break // Cancelled
                }
            }
        }

        // Wait for Enter to stop
        _ = readLine()
        let stopTime = ContinuousClock.now

        // Stop recording
        engine.stop()
        inputNode.removeTap(onBus: 0)
        vadTask.cancel()

        // Small delay to let the task clean up
        try await Task.sleep(for: .milliseconds(50))

        // Process remaining audio through VAD
        let remainingSamples = sampleBuffer.samples(from: state.vadCursor)
        if !remainingSamples.isEmpty {
            let events = processor.process(samples: remainingSamples)
            for event in events {
                if case .speechEnded(let segment) = event {
                    let allSamples = sampleBuffer.samples
                    let startIdx = max(0, Int(segment.startTime * 16000))
                    let endIdx = min(Int(segment.endTime * 16000), allSamples.count)
                    guard startIdx < endIdx else { continue }
                    let segmentAudio = Array(allSamples[startIdx..<endIdx])

                    let sttStart = ContinuousClock.now
                    let text = asrModel.transcribe(audio: segmentAudio, sampleRate: 16000, language: language)
                    let sttTime = ContinuousClock.now - sttStart

                    state.segmentTexts.append((text: text, sttDuration: sttTime, startTime: segment.startTime, endTime: segment.endTime))
                    print("  [Segment \(state.segmentTexts.count)] \"\(text)\" (\(String(format: "%.1f", segment.startTime))-\(String(format: "%.1f", segment.endTime))s, STT: \(formatMs(sttTime)))")
                }
            }
        }

        // Flush VAD to catch any remaining speech
        let flushEvents = processor.flush()
        for event in flushEvents {
            if case .speechEnded(let segment) = event {
                let allSamples = sampleBuffer.samples
                let startIdx = max(0, Int(segment.startTime * 16000))
                let endIdx = min(Int(segment.endTime * 16000), allSamples.count)
                guard startIdx < endIdx else { continue }
                let segmentAudio = Array(allSamples[startIdx..<endIdx])

                let sttStart = ContinuousClock.now
                let text = asrModel.transcribe(audio: segmentAudio, sampleRate: 16000, language: language)
                let sttTime = ContinuousClock.now - sttStart

                state.segmentTexts.append((text: text, sttDuration: sttTime, startTime: segment.startTime, endTime: segment.endTime))
                print("  [Segment \(state.segmentTexts.count)] \"\(text)\" (flush, \(String(format: "%.1f", segment.startTime))-\(String(format: "%.1f", segment.endTime))s, STT: \(formatMs(sttTime)))")
            }
        }

        let afterStreamTime = ContinuousClock.now

        // Total audio
        let allSamples = sampleBuffer.samples
        let audioDuration = Double(allSamples.count) / 16000.0

        guard !state.segmentTexts.isEmpty else {
            print("\n  [VAD] Keine Sprache erkannt.")
            continue
        }

        // Streaming results
        let streamText = state.segmentTexts.map(\.text).joined(separator: " ")
        let lastSegmentSTT = state.segmentTexts.last!.sttDuration
        let totalSTT = state.segmentTexts.reduce(Duration.zero) { $0 + $1.sttDuration }
        let preTranscribed = state.segmentTexts.count - 1 // segments transcribed during recording
        let latencyAfterStop = afterStreamTime - stopTime

        // Timing table
        printTimingTable([
            ("Aufnahme-Dauer", "\(String(format: "%.1f", audioDuration))s"),
            ("Segmente", "\(state.segmentTexts.count)"),
            ("Voraus-transkribiert", "\(max(0, preTranscribed)) (während Aufnahme)"),
            ("Letztes Segment STT", formatMs(lastSegmentSTT)),
            ("Latenz nach Stop", formatMs(latencyAfterStop)),
            ("Gesamt-STT", "\(formatMs(totalSTT)) (alle Segmente)"),
        ])

        print("  Stream-Text: \(streamText)")
    }
}

// MARK: - Batch Mode

struct BatchResult {
    let file: String
    let audioDuration: Double
    let transcribeMs: Int64
    let rtf: Double
    let text: String
    let expected: String?
}

func runBatchMode(directory: String, language: String) async throws {
    print("=== SpeechSwiftTestCLI — Batch Mode ===")
    print("Verzeichnis: \(directory)")
    print("Sprache:     \(language)")
    print("")

    // 1. Find audio files
    let fm = FileManager.default
    let dirURL = URL(fileURLWithPath: directory)
    let contents = try fm.contentsOfDirectory(
        at: dirURL,
        includingPropertiesForKeys: nil
    )
    let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "caf", "aiff", "flac"]
    let audioFiles = contents
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !audioFiles.isEmpty else {
        print("Keine Audio-Dateien gefunden in \(directory)")
        exit(1)
    }
    print("Gefunden: \(audioFiles.count) Audio-Datei(en)")

    // 2. Load models (einmalig)
    let (asrModel, modelLoadTime) = try await loadASRModel()
    let (vadModel, vadLoadTime) = try await loadVADModel()
    print("")

    // 3. Transcribe each file
    var results: [BatchResult] = []

    for (index, fileURL) in audioFiles.enumerated() {
        let fileName = fileURL.lastPathComponent
        print("[\(index + 1)/\(audioFiles.count)] \(fileName)")

        let (samples, audioDuration) = try AudioLoader.loadSamples(from: fileURL.path)

        // VAD-Gate: skip transcription if no speech detected
        let vadSegments = vadModel.detectSpeech(audio: samples, sampleRate: 16000)
        let text: String
        let transcribeTime: Duration

        if vadSegments.isEmpty {
            text = ""
            transcribeTime = .zero
            print("  [VAD] Keine Sprache erkannt, überspringe Transkription.")
        } else {
            let transcribeStart = ContinuousClock.now
            text = asrModel.transcribe(
                audio: samples,
                sampleRate: 16000,
                language: language
            )
            transcribeTime = ContinuousClock.now - transcribeStart
        }
        let transcribeMs = transcribeTime.components.seconds * 1000
            + transcribeTime.components.attoseconds / 1_000_000_000_000_000
        let rtf = Double(transcribeMs) / (audioDuration * 1000)

        // Check for expected text
        let baseName = fileURL.deletingPathExtension().path
        let expectedTxt = baseName + ".txt"
        let expectedLong = baseName + ".expected.txt"
        let expectedPath = fm.fileExists(atPath: expectedTxt) ? expectedTxt : expectedLong
        let expected: String? = fm.fileExists(atPath: expectedPath)
            ? try? String(contentsOfFile: expectedPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        results.append(BatchResult(
            file: fileName,
            audioDuration: audioDuration,
            transcribeMs: transcribeMs,
            rtf: rtf,
            text: text,
            expected: expected
        ))

        print("  Text:  \(text)")
        if let expected {
            let match = text.trimmingCharacters(in: .whitespacesAndNewlines) == expected
            print("  Soll:  \(expected)")
            print("  Match: \(match ? "JA" : "NEIN")")
        }
        print("  Zeit:  \(transcribeMs)ms (RTF \(String(format: "%.3f", rtf)))")
        print("")
    }

    // 4. Summary table
    print("=== Zusammenfassung ===")
    print("")
    let maxName = results.map(\.file.count).max() ?? 10
    let header = "Datei".padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
    print("  \(header)Dauer     STT       RTF       Match")
    print("  \(String(repeating: "─", count: maxName + 42))")

    for r in results {
        let name = r.file.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
        let dur = "\(String(format: "%.1f", r.audioDuration))s".padding(toLength: 10, withPad: " ", startingAt: 0)
        let stt = "\(r.transcribeMs)ms".padding(toLength: 10, withPad: " ", startingAt: 0)
        let rtf = String(format: "%.3f", r.rtf).padding(toLength: 10, withPad: " ", startingAt: 0)
        let match: String
        if let expected = r.expected {
            match = r.text.trimmingCharacters(in: .whitespacesAndNewlines) == expected ? "JA" : "NEIN"
        } else {
            match = "—"
        }
        print("  \(name)\(dur)\(stt)\(rtf)\(match)")
    }

    let avgMs = results.map(\.transcribeMs).reduce(0, +) / Int64(results.count)
    let avgRtf = results.map(\.rtf).reduce(0, +) / Double(results.count)
    print("")
    print("  Durchschnitt: \(avgMs)ms STT, RTF \(String(format: "%.3f", avgRtf))")
    print("  Modell laden: \(formatMs(modelLoadTime)), VAD laden: \(formatMs(vadLoadTime))")

    let matchCount = results.filter { r in
        guard let expected = r.expected else { return false }
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines) == expected
    }.count
    let totalWithExpected = results.filter { $0.expected != nil }.count
    if totalWithExpected > 0 {
        print("  Matches: \(matchCount)/\(totalWithExpected)")
    }

    print("\nPASS")
}

// MARK: - Main

Task {
    do {
        switch mode {
        case "file":
            let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
            guard !path.isEmpty else {
                print("Fehler: Audio-Pfad erforderlich.")
                print(usage)
                exit(1)
            }
            let language = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "de"
            try await runFileMode(path: path, language: language)

        case "live":
            let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "de"
            try await runLiveMode(language: language)

        case "stream":
            let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "de"
            try await runStreamMode(language: language)

        case "batch":
            let dir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
            guard !dir.isEmpty else {
                print("Fehler: Verzeichnis-Pfad erforderlich.")
                print(usage)
                exit(1)
            }
            let language = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "de"
            try await runBatchMode(directory: dir, language: language)

        default:
            print("Unbekannter Modus: \(mode)")
            print(usage)
            exit(1)
        }
    } catch {
        print("\nFEHLER:")
        print("  Typ:  \(type(of: error))")
        print("  Desc: \(error)")
        exit(1)
    }

    exit(0)
}

RunLoop.main.run()
