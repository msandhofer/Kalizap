import Foundation
import Kalizap
import STTTestCommon

// MARK: - Batch Mode

struct BatchResult {
    let file: String
    let audioDuration: Double
    let transcribeMs: Int64
    let rtf: Double
    let text: String
    let expected: String?
    let wer: Double?
}

func runBatchMode(directory: String, modelName: String, language: String?, coreml: Bool = false) async throws {
    print("=== WhisperCppTestCLI — Batch Mode ===")
    print("Verzeichnis: \(directory)")
    print("Modell:      \(modelName)")
    print("Sprache:     \(language ?? "auto")")
    print("")

    // 1. Find audio files
    let fm = FileManager.default
    let dirURL = URL(fileURLWithPath: directory)
    let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
    let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "caf", "aiff", "flac"]
    let audioFiles = contents
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !audioFiles.isEmpty else {
        print("Keine Audio-Dateien gefunden in \(directory)")
        exit(1)
    }
    print("Gefunden: \(audioFiles.count) Audio-Datei(en)")

    // 2. Load model (einmalig)
    let lang: TranscriptionLanguage = language == "en" ? .english : .german
    let (backend, modelLoadTime) = try await loadWhisperCppModel(name: modelName, language: lang, coreml: coreml)
    let languageStr = language ?? "de"
    print("")

    // 3. Transcribe each file
    var results: [BatchResult] = []

    for (index, fileURL) in audioFiles.enumerated() {
        let fileName = fileURL.lastPathComponent
        print("[\(index + 1)/\(audioFiles.count)] \(fileName)")

        let (samples, audioDuration) = try AudioLoader.loadSamples(from: fileURL.path)

        let transcribeStart = ContinuousClock.now
        let result = try await backend.transcribe(
            samples: samples,
            language: languageStr,
            prompt: ""
        )
        let transcribeTime = ContinuousClock.now - transcribeStart
        let transcribeMs = durationToMs(transcribeTime)
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

        let wer: Double? = expected.map { exp in
            WERScoring.calculate(hypothesis: result.text, reference: exp).wer
        }

        results.append(BatchResult(
            file: fileName,
            audioDuration: audioDuration,
            transcribeMs: transcribeMs,
            rtf: rtf,
            text: result.text,
            expected: expected,
            wer: wer
        ))

        print("  Text:  \(result.text)")
        if let expected {
            print("  Soll:  \(expected)")
            if let wer {
                print("  WER:   \(String(format: "%.1f", wer * 100))%")
            }
        }
        print("  Zeit:  \(transcribeMs)ms (RTF \(String(format: "%.3f", rtf)))")
        print("")
    }

    // 4. Summary table
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
    print("  Modell laden: \(formatMs(modelLoadTime))")

    print("\nPASS")
}
