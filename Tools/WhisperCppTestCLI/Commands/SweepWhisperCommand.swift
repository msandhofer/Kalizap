import Foundation
import Kalizap
import STTTestCommon

func runSweepWhisperMode(args: SweepWhisperArgs) async throws {
    let dir = args.directory

    // Parameter grid
    let fallbackIntervals: [Double] = [1.5, 2.0, 3.0, 4.0]
    let tailIntervals: [Double] = [0, 1.0, 1.5, 2.0]
    let partialAccepts: [Double] = [0, 0.3, 0.5, 1.0]

    print("=== StreamWait Parameter Sweep ===")
    print("Verzeichnis:  \(dir)")
    print("Modell:       \(args.modelName)\(args.coreml ? " (CoreML)" : "")")
    print("Fallback:     \(fallbackIntervals)")
    print("Tail:         \(tailIntervals)")
    print("Partial:      \(partialAccepts)")
    print()

    // Load audio files
    let fm = FileManager.default
    let audioExtensions = ["m4a", "wav", "mp3", "caf", "aiff", "flac"]
    let allFiles = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
    let audioFiles = allFiles.filter { f in
        audioExtensions.contains((f as NSString).pathExtension.lowercased())
    }.sorted()

    guard !audioFiles.isEmpty else {
        print("Keine Audiodateien gefunden in \(dir)")
        exit(1)
    }

    // Pre-load audio + expected text
    var audioData: [(file: String, samples: [Float], expected: String?)] = []
    for file in audioFiles {
        let path = (dir as NSString).appendingPathComponent(file)
        let (samples, _) = try AudioLoader.loadSamples(from: path)
        let baseName = (path as NSString).deletingPathExtension
        let expected = (try? String(contentsOfFile: baseName + ".txt", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip silent files (empty expected text)
        if let exp = expected, exp.isEmpty { continue }
        audioData.append((file: file, samples: samples, expected: expected))
    }

    print("\(audioData.count) Audiodateien geladen")

    // Load model
    let (backend, loadTime) = try await loadWhisperCppModel(
        name: args.modelName,
        language: .german,
        coreml: args.coreml
    )
    print("Modell geladen in \(loadTime.formatted())")
    print()

    // Sweep
    var allResults: [WhisperStreamResult] = []
    var aggregated: [(params: WhisperStreamParams, avgWER: Double, avgStreamWaitMs: Int, avgTotalDecodeMs: Int, fileCount: Int)] = []
    var configIndex = 0

    for fb in fallbackIntervals {
        for tail in tailIntervals {
            // Skip redundant: aggressive tail + aggressive fallback
            if tail > 0 && fb < 3.0 { continue }

            for pa in partialAccepts {
                configIndex += 1
                let params = WhisperStreamParams(
                    fallbackInterval: fb,
                    tailInterval: tail,
                    partialAccept: pa
                )

                var werValues: [Double] = []
                var swValues: [Int] = []
                var tdValues: [Int] = []

                print("  [\(configIndex)] fb=\(fb)s tail=\(tail)s pa=\(pa)s ", terminator: "")
                fflush(stdout)

                for item in audioData {
                    let sim = try await simulateWhisperStream(
                        samples: item.samples,
                        backend: backend,
                        language: args.language ?? "de",
                        fallbackInterval: fb,
                        tailInterval: tail,
                        partialAccept: pa,
                        verbose: false
                    )

                    let wer: Double?
                    if let expected = item.expected {
                        wer = WERScoring.calculate(hypothesis: sim.text, reference: expected).wer
                    } else {
                        wer = nil
                    }

                    if let w = wer { werValues.append(w) }
                    swValues.append(sim.streamWaitMs)
                    tdValues.append(sim.totalDecodeMs)

                    allResults.append(WhisperStreamResult(
                        file: item.file,
                        engine: "whisper.cpp-\(args.modelName)",
                        params: params,
                        wer: wer,
                        streamWaitMs: sim.streamWaitMs,
                        totalDecodeMs: sim.totalDecodeMs,
                        decodeCount: sim.decodeCount,
                        deltaSeconds: sim.deltaSeconds,
                        usedPartial: sim.usedPartial,
                        text: sim.text,
                        expected: item.expected
                    ))
                    print(".", terminator: "")
                    fflush(stdout)
                }

                let avgWER = werValues.isEmpty ? 0 : werValues.reduce(0, +) / Double(werValues.count)
                let avgSW = swValues.isEmpty ? 0 : swValues.reduce(0, +) / swValues.count
                let avgTD = tdValues.isEmpty ? 0 : tdValues.reduce(0, +) / tdValues.count

                print(" WER=\(String(format: "%.1f", avgWER * 100))% SW=\(avgSW)ms TD=\(avgTD)ms")

                aggregated.append((
                    params: params,
                    avgWER: avgWER,
                    avgStreamWaitMs: avgSW,
                    avgTotalDecodeMs: avgTD,
                    fileCount: audioData.count
                ))
            }
        }
    }

    // Pareto analysis
    let entries = ParetoFilter.markWhisperPareto(aggregated)
    let sweepResult = WhisperSweepResult(
        engine: "whisper.cpp-\(args.modelName)",
        entries: entries,
        details: allResults
    )

    if args.json {
        print(try TestResultJSON.encode(sweepResult))
    } else {
        print()
        print("=== Sweep Ergebnis ===")
        print()
        let header = "FB".padding(toLength: 6, withPad: " ", startingAt: 0)
            + "Tail".padding(toLength: 6, withPad: " ", startingAt: 0)
            + "PA".padding(toLength: 6, withPad: " ", startingAt: 0)
            + "WER".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "SW-ms".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "TD-ms".padding(toLength: 8, withPad: " ", startingAt: 0)
            + "Pareto"
        print(header)
        print(String(repeating: "-", count: 48))
        for e in entries.sorted(by: { $0.avgWER < $1.avgWER }) {
            var line = "\(e.params.fallbackInterval)".padding(toLength: 6, withPad: " ", startingAt: 0)
            line += "\(e.params.tailInterval)".padding(toLength: 6, withPad: " ", startingAt: 0)
            line += "\(e.params.partialAccept)".padding(toLength: 6, withPad: " ", startingAt: 0)
            line += "\(String(format: "%.1f%%", e.avgWER * 100))".padding(toLength: 8, withPad: " ", startingAt: 0)
            line += "\(e.avgStreamWaitMs)".padding(toLength: 8, withPad: " ", startingAt: 0)
            line += "\(e.avgTotalDecodeMs)".padding(toLength: 8, withPad: " ", startingAt: 0)
            line += e.paretoOptimal ? " *" : ""
            print(line)
        }
    }
}
