import AVFoundation
import Foundation
import Speech
import STTTestCommon

// MARK: - Batch Command (offline, directory + WER)
// Note: SpeechAnalyzer locks its internal worker after the first analyzeSequence call.
// Batch mode works around this by spawning a subprocess per file.

@available(macOS 26, *)
func runBatchMode(args: BatchArgs) async throws {
    let locale = resolveLocale(args.locale)
    let isJSON = args.json

    if !isJSON {
        print("=== SpeechAnalyzerTestCLI — Batch Mode ===")
        print("Verzeichnis: \(args.directory)")
        print("Locale:      \(locale.identifier)")
        print("")
    }

    // 1. Find audio files
    let fm = FileManager.default
    let dirURL = URL(fileURLWithPath: args.directory)
    let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
    let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "caf", "aiff", "flac"]
    let audioFiles = contents
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !audioFiles.isEmpty else {
        print("Keine Audio-Dateien gefunden in \(args.directory)")
        exit(1)
    }
    if !isJSON { print("Gefunden: \(audioFiles.count) Audio-Datei(en)\n") }

    // 2. Ensure locale installed
    let setupStart = ContinuousClock.now
    let checkTranscriber = createTranscriber(locale: locale, preset: .transcription)
    try await ensureLocaleInstalled(locale: locale, transcriber: checkTranscriber)
    let setupTime = ContinuousClock.now - setupStart

    // 3. Transcribe each file via subprocess (workaround for worker-lock issue)
    let executablePath = CommandLine.arguments[0]
    var results: [SpeechAnalyzerBatchEntry] = []

    for (index, fileURL) in audioFiles.enumerated() {
        let fileName = fileURL.lastPathComponent
        if !isJSON { print("[\(index + 1)/\(audioFiles.count)] \(fileName)") }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        // Run transcribe in subprocess
        let transcribeStart = ContinuousClock.now
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["transcribe-raw", fileURL.path, "--locale", args.locale]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let transcribeMs = durationToMs(ContinuousClock.now - transcribeStart)
        let rtf = Double(transcribeMs) / (audioDuration * 1000)

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = (String(data: outputData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Load expected text for WER
        let baseName = fileURL.deletingPathExtension().path
        let expectedTxt = baseName + ".txt"
        let expectedLong = baseName + ".expected.txt"
        let expectedPath = fm.fileExists(atPath: expectedTxt) ? expectedTxt : expectedLong
        let expected: String? = fm.fileExists(atPath: expectedPath)
            ? try? String(contentsOfFile: expectedPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        let wer: Double? = expected.flatMap { exp in
            guard !exp.isEmpty, !text.isEmpty else { return nil }
            return WERScoring.calculate(hypothesis: text, reference: exp).wer
        }

        results.append(SpeechAnalyzerBatchEntry(
            file: fileName,
            audioDuration: audioDuration,
            transcribeMs: transcribeMs,
            rtf: rtf,
            text: text,
            expected: expected,
            wer: wer
        ))

        if !isJSON {
            print("  Text:  \(text.prefix(80))\(text.count > 80 ? "..." : "")")
            if let expected, !expected.isEmpty {
                print("  Soll:  \(expected.prefix(80))\(expected.count > 80 ? "..." : "")")
                if let wer { print("  WER:   \(String(format: "%.1f", wer * 100))%") }
            }
            print("  Zeit:  \(transcribeMs)ms (RTF \(String(format: "%.3f", rtf)))")
            print("")
        }
    }

    // 4. Output
    if isJSON {
        let output = SpeechAnalyzerBatchResult(
            engine: "SpeechAnalyzer",
            locale: locale.identifier,
            results: results.map {
                SpeechAnalyzerResult(
                    file: $0.file,
                    locale: locale.identifier,
                    wer: $0.wer,
                    transcribeMs: Int($0.transcribeMs),
                    audioDurationSeconds: $0.audioDuration,
                    rtf: $0.rtf,
                    text: $0.text,
                    expected: $0.expected
                )
            }
        )
        print(try TestResultJSON.encode(output))
    } else {
        // Summary table
        print("=== Zusammenfassung ===")
        print("")
        let maxName = results.map(\.file.count).max() ?? 10
        let header = "Datei".padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
        print("  \(header)Dauer     STT       RTF       WER")
        print("  \(String(repeating: "─", count: maxName + 42))")

        for r in results {
            let name = r.file.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
            let dur = "\(String(format: "%.1f", r.audioDuration))s".padding(toLength: 10, withPad: " ", startingAt: 0)
            let stt = "\(r.transcribeMs)ms".padding(toLength: 10, withPad: " ", startingAt: 0)
            let rtf = String(format: "%.3f", r.rtf).padding(toLength: 10, withPad: " ", startingAt: 0)
            let werStr: String
            if let wer = r.wer {
                werStr = String(format: "%.1f%%", wer * 100)
            } else {
                werStr = "—"
            }
            print("  \(name)\(dur)\(stt)\(rtf)\(werStr)")
        }

        let avgMs = results.map(\.transcribeMs).reduce(0, +) / Int64(results.count)
        let avgRtf = results.map(\.rtf).reduce(0, +) / Double(results.count)
        let werResults = results.compactMap(\.wer)
        let avgWer = werResults.isEmpty ? nil : werResults.reduce(0, +) / Double(werResults.count)

        print("")
        print("  Durchschnitt: \(avgMs)ms STT, RTF \(String(format: "%.3f", avgRtf))")
        if let avgWer {
            print("  Durchschnitt WER: \(String(format: "%.1f", avgWer * 100))%")
        }
        print("  Setup/Locale: \(formatMs(setupTime))")

        print("\nPASS")
    }
}

// MARK: - Internal Batch Types

struct SpeechAnalyzerBatchEntry {
    let file: String
    let audioDuration: Double
    let transcribeMs: Int64
    let rtf: Double
    let text: String
    let expected: String?
    let wer: Double?
}
