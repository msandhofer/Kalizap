import Foundation
import Kalizap
import SpeechVAD
import STTTestCommon

// MARK: - Sweep Mode

func runSweepMode(args: SweepArgs) async throws {
    let isJSON = args.json

    if !isJSON {
        print("=== WhisperCppTestCLI — Sweep Mode ===")
        print("Verzeichnis: \(args.directory)")
        print("Modell:      \(args.modelName)")
        print("Sprache:     \(args.language ?? "auto")")
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

    if !isJSON {
        print("Gefunden: \(audioFiles.count) Audio-Datei(en)")
    }

    // 2. Load models (einmalig)
    let lang: TranscriptionLanguage = args.language == "en" ? .english : .german
    let (backend, _) = try await loadWhisperCppModel(name: args.modelName, language: lang, coreml: args.coreml)
    let (vadModel, _) = try await loadVADModel()

    // 3. Parameter grid
    let minSegments: [Float] = [2, 3, 4, 5]
    let maxSegments: [Float] = [5, 7, 10]
    let minSilences: [Double] = [0.3, 0.4, 0.5, 0.6]

    let totalCombinations = minSegments.count * maxSegments.count * minSilences.count
    if !isJSON {
        print("Parameter-Kombinationen: \(totalCombinations)")
        print("Gesamt-Durchläufe: \(totalCombinations) × \(audioFiles.count) Dateien = \(totalCombinations * audioFiles.count)")
        print("")
    }

    // 4. Pre-load all audio files
    var audioData: [(url: URL, samples: [Float], duration: Double, expected: String?)] = []
    for fileURL in audioFiles {
        let (samples, duration) = try AudioLoader.loadSamples(from: fileURL.path)
        let baseName = fileURL.deletingPathExtension().path
        let expectedTxt = baseName + ".txt"
        let expectedLong = baseName + ".expected.txt"
        let expectedPath = fm.fileExists(atPath: expectedTxt) ? expectedTxt : expectedLong
        let expected: String? = fm.fileExists(atPath: expectedPath)
            ? try? String(contentsOfFile: expectedPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        audioData.append((url: fileURL, samples: samples, duration: duration, expected: expected))
    }

    // 5. Run sweep
    let languageStr = args.language ?? "de"
    var allDetails: [StreamFileResult] = []
    var aggregated: [(params: StreamFileParams, avgWER: Double, avgLatencyMs: Int, fileCount: Int)] = []
    var runIndex = 0

    for minSeg in minSegments {
        for maxSeg in maxSegments {
            guard maxSeg > minSeg else { continue }
            for minSil in minSilences {
                runIndex += 1
                let params = StreamFileParams(
                    minSegment: Double(minSeg),
                    maxSegment: Double(maxSeg),
                    minSilence: minSil
                )

                var werValues: [Double] = []
                var latencyValues: [Int] = []

                for audio in audioData {
                    let result = try await simulateStream(
                        samples: audio.samples,
                        audioDuration: audio.duration,
                        backend: backend,
                        vadModel: vadModel,
                        language: languageStr,
                        minSegment: minSeg,
                        maxSegment: maxSeg,
                        minSilence: minSil,
                        verbose: false
                    )

                    let werResult: Double? = audio.expected.map { exp in
                        WERScoring.calculate(hypothesis: result.text, reference: exp).wer
                    }

                    let detail = StreamFileResult(
                        file: audio.url.lastPathComponent,
                        engine: "whisper.cpp-\(args.modelName)",
                        params: params,
                        segments: result.segmentCount,
                        wer: werResult,
                        latency_after_stop_ms: result.latencyAfterStopMs,
                        total_stt_ms: result.totalSttMs,
                        text: result.text,
                        expected: audio.expected
                    )
                    allDetails.append(detail)

                    if let wer = werResult {
                        werValues.append(wer)
                    }
                    latencyValues.append(result.latencyAfterStopMs)
                }

                let avgWER = werValues.isEmpty ? 1.0 : werValues.reduce(0, +) / Double(werValues.count)
                let avgLatency = latencyValues.isEmpty ? 0 : latencyValues.reduce(0, +) / latencyValues.count

                aggregated.append((params: params, avgWER: avgWER, avgLatencyMs: avgLatency, fileCount: audioData.count))

                if !isJSON {
                    print("  [\(runIndex)/\(totalCombinations)] minSeg=\(minSeg) maxSeg=\(maxSeg) minSil=\(minSil) → WER \(String(format: "%.1f", avgWER * 100))% Latenz \(avgLatency)ms")
                }
            }
        }
    }

    // 6. Pareto analysis
    let entries = ParetoFilter.markPareto(aggregated)

    if isJSON {
        let sweepResult = SweepResult(engine: "whisper.cpp-\(args.modelName)", entries: entries, details: allDetails)
        print(try TestResultJSON.encode(sweepResult))
    } else {
        let sorted = entries.sorted { $0.avgWER < $1.avgWER }
        print("")
        print("=== Ergebnisse (sortiert nach WER) ===")
        print("")
        print("  minSeg  maxSeg  minSil  WER      Latenz   Pareto")
        print("  \(String(repeating: "─", count: 55))")

        for entry in sorted {
            let pareto = entry.paretoOptimal ? " *" : ""
            print("  \(String(format: "%5.0f", entry.params.minSegment))   \(String(format: "%5.0f", entry.params.maxSegment))   \(String(format: "%4.1f", entry.params.minSilence))    \(String(format: "%5.1f", entry.avgWER * 100))%   \(String(format: "%5d", entry.avgLatencyMs))ms\(pareto)")
        }

        let paretoCount = entries.filter(\.paretoOptimal).count
        print("")
        print("  * = Pareto-optimal (beste WER bei Latenz < 600ms)")
        print("  \(paretoCount) Pareto-optimale Konfiguration(en) gefunden")
        print("\nPASS")
    }
}
