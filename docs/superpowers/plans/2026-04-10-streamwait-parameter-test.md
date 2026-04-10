# StreamWait Parameter Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Neuer `stream-whisper` CLI-Command, der die App-Streaming-Architektur (WhisperTranscriptionEngine) deterministisch auf Audiodateien simuliert. Parametrisierbar fuer Fallback-Intervall, Tail-Decode-Intervall und Partial-Accept-Schwelle. Sweep-Command fuer automatischen Vergleich.

**Architecture:** Zwei neue Commands im bestehenden WhisperCppTestCLI: `stream-whisper` (Einzeldatei) und `sweep-whisper` (Parameter-Grid). Neue Typen in STTTestCommon fuer die erweiterten Parameter und Metriken. Die Simulation bildet die WhisperTranscriptionEngine.transcribe() Logik 1:1 nach, aber deterministisch (Audiodatei statt Mikrofon).

**Tech Stack:** Swift, WhisperCppBackend (whisper.cpp + VAD), STTTestCommon (WER, Pareto), ContinuousClock fuer Timing

---

### Task 1: Erweiterte Typen in STTTestCommon

**Files:**
- Modify: `Tools/STTTestCommon/TestResult.swift`

- [ ] **Step 1: WhisperStreamParams hinzufuegen**

In `Tools/STTTestCommon/TestResult.swift` nach Zeile 15 (nach StreamFileParams) einfuegen:

```swift
public struct WhisperStreamParams: Codable, Sendable {
    public let fallbackInterval: Double   // Sekunden, Default 4.0
    public let tailInterval: Double       // Sekunden, 0 = aus
    public let partialAccept: Double      // Sekunden, 0 = aus

    public init(fallbackInterval: Double, tailInterval: Double, partialAccept: Double) {
        self.fallbackInterval = fallbackInterval
        self.tailInterval = tailInterval
        self.partialAccept = partialAccept
    }
}
```

- [ ] **Step 2: WhisperStreamResult hinzufuegen**

Nach dem neuen WhisperStreamParams:

```swift
public struct WhisperStreamResult: Codable, Sendable {
    public let file: String
    public let engine: String
    public let params: WhisperStreamParams
    public let wer: Double?
    public let streamWaitMs: Int          // Delta-Decode Dauer (oder 0 bei Partial-Accept)
    public let totalDecodeMs: Int         // Kumulative Decode-Zeit aller Decodes
    public let decodeCount: Int           // Anzahl Decodes waehrend Simulation
    public let deltaSeconds: Double       // Audio-Delta nach letztem Decode bei Stop
    public let usedPartial: Bool          // true wenn Partial/Tail statt Delta-Decode
    public let text: String
    public let expected: String?

    public init(
        file: String, engine: String, params: WhisperStreamParams,
        wer: Double?, streamWaitMs: Int, totalDecodeMs: Int,
        decodeCount: Int, deltaSeconds: Double, usedPartial: Bool,
        text: String, expected: String?
    ) {
        self.file = file
        self.engine = engine
        self.params = params
        self.wer = wer
        self.streamWaitMs = streamWaitMs
        self.totalDecodeMs = totalDecodeMs
        self.decodeCount = decodeCount
        self.deltaSeconds = deltaSeconds
        self.usedPartial = usedPartial
        self.text = text
        self.expected = expected
    }
}
```

- [ ] **Step 3: WhisperSweepEntry und WhisperSweepResult hinzufuegen**

```swift
public struct WhisperSweepEntry: Codable, Sendable {
    public let params: WhisperStreamParams
    public let avgWER: Double
    public let avgStreamWaitMs: Int
    public let avgTotalDecodeMs: Int
    public let fileCount: Int
    public let paretoOptimal: Bool

    public init(params: WhisperStreamParams, avgWER: Double, avgStreamWaitMs: Int, avgTotalDecodeMs: Int, fileCount: Int, paretoOptimal: Bool) {
        self.params = params
        self.avgWER = avgWER
        self.avgStreamWaitMs = avgStreamWaitMs
        self.avgTotalDecodeMs = avgTotalDecodeMs
        self.fileCount = fileCount
        self.paretoOptimal = paretoOptimal
    }
}

public struct WhisperSweepResult: Codable, Sendable {
    public let engine: String
    public let entries: [WhisperSweepEntry]
    public let details: [WhisperStreamResult]

    public init(engine: String, entries: [WhisperSweepEntry], details: [WhisperStreamResult]) {
        self.engine = engine
        self.entries = entries
        self.details = details
    }
}
```

- [ ] **Step 4: ParetoFilter fuer WhisperStream erweitern**

In `ParetoFilter` eine zweite Methode hinzufuegen:

```swift
    public static func markWhisperPareto(
        _ entries: [(params: WhisperStreamParams, avgWER: Double, avgStreamWaitMs: Int, avgTotalDecodeMs: Int, fileCount: Int)],
        maxStreamWaitMs: Int = 500
    ) -> [WhisperSweepEntry] {
        let eligible = entries.filter { $0.avgStreamWaitMs < maxStreamWaitMs }

        return entries.map { entry in
            let isPareto: Bool
            if entry.avgStreamWaitMs >= maxStreamWaitMs {
                isPareto = false
            } else {
                isPareto = !eligible.contains { other in
                    other.avgWER < entry.avgWER && other.avgStreamWaitMs < entry.avgStreamWaitMs
                        && !(other.avgWER == entry.avgWER && other.avgStreamWaitMs == entry.avgStreamWaitMs)
                }
            }
            return WhisperSweepEntry(
                params: entry.params,
                avgWER: entry.avgWER,
                avgStreamWaitMs: entry.avgStreamWaitMs,
                avgTotalDecodeMs: entry.avgTotalDecodeMs,
                fileCount: entry.fileCount,
                paretoOptimal: isPareto
            )
        }
    }
```

- [ ] **Step 5: Kompilierung pruefen**

Run: `swift build --target STTTestCommon 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Tools/STTTestCommon/TestResult.swift
git commit -m "feat(#36): WhisperStream Typen fuer StreamWait Parameter Tests"
```

---

### Task 2: stream-whisper Command — Simulations-Kern

**Files:**
- Create: `Tools/WhisperCppTestCLI/Commands/StreamWhisperCommand.swift`

Dies ist der Kern: eine Funktion `simulateWhisperStream()` die die WhisperTranscriptionEngine.transcribe() Logik deterministisch nachbildet.

- [ ] **Step 1: StreamWhisperCommand.swift erstellen**

Create `Tools/WhisperCppTestCLI/Commands/StreamWhisperCommand.swift`:

```swift
import Foundation
import DerFluisterer
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

    let sampleRate: Int = 16000
    let pollingIntervalMs: Int = 200
    let minSamplesForDecode = sampleRate  // 1 second

    // State
    var accumulatedText = ""
    var lastDecodedSampleCount = 0
    var lastDecodeTime = ContinuousClock.now
    var lastKnownBoundaryCount = 0
    var totalDecodeMs = 0
    var decodeCount = 0

    // Tail-Decode Cache
    var cachedTailText = ""
    var cachedTailSampleCount = 0
    var lastTailDecodeTime = ContinuousClock.now

    // Simulate the streaming consumer loop
    // In the real app, audio arrives in real-time. Here we simulate
    // by processing the full buffer but stepping through it in
    // pollingIntervalMs increments based on simulated time.
    //
    // Simulated time: each polling tick = pollingIntervalMs of audio.
    // At each tick, we have `samplesAvailable` = min(tick * sampleRate * pollingInterval / 1000, totalSamples).

    let totalSamples = samples.count
    let samplesPerTick = sampleRate * pollingIntervalMs / 1000  // 3200 at 200ms

    var simulatedSampleCount = 0
    var tickCount = 0

    // Consumer loop: simulate 200ms polling ticks
    while simulatedSampleCount < totalSamples {
        tickCount += 1
        simulatedSampleCount = min(tickCount * samplesPerTick, totalSamples)

        guard simulatedSampleCount >= minSamplesForDecode else { continue }

        // VAD boundary detection
        let currentSamples = Array(samples.prefix(simulatedSampleCount))
        let boundaries = backend.detectSilenceBoundaries(samples: currentSamples)

        let timeSinceLastDecode = Double(tickCount * pollingIntervalMs - (decodeCount > 0 ? Int(totalDecodeMs) : 0)) / 1000.0
        let hasNewBoundary = boundaries.count > lastKnownBoundaryCount
        let fallbackNeeded = timeSinceLastDecode >= fallbackInterval
            && simulatedSampleCount > lastDecodedSampleCount + minSamplesForDecode

        // Tail-decode check
        let tailNeeded = tailInterval > 0
            && lastDecodedSampleCount > 0
            && (ContinuousClock.now - lastTailDecodeTime).components.seconds >= Int64(tailInterval)

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
            let decodeMs = Int((ContinuousClock.now - decodeStart).components.attoseconds / 1_000_000_000_000_000)

            accumulatedText = result.text
            lastDecodedSampleCount = samplesToDecodeCount
            lastDecodeTime = ContinuousClock.now
            totalDecodeMs += decodeMs
            decodeCount += 1

            // Reset tail cache after VAD decode
            cachedTailText = ""
            cachedTailSampleCount = 0
            lastTailDecodeTime = ContinuousClock.now

            if verbose {
                print("    VAD decode #\(decodeCount): \(samplesToDecodeCount) samples, \(decodeMs)ms, text=\(result.text.prefix(40))...")
            }
        }

        // Speculative tail decode (Ansatz C)
        if tailNeeded && lastDecodedSampleCount > 0 && simulatedSampleCount > lastDecodedSampleCount + 1600 {
            let tailSamples = Array(samples[lastDecodedSampleCount..<simulatedSampleCount])
            var normalizedTail = tailSamples
            AudioProcessingUtils.peakNormalize(&normalizedTail)

            let decodeStart = ContinuousClock.now
            let tailResult = try await backend.transcribe(
                samples: normalizedTail,
                language: language,
                prompt: accumulatedText
            )
            let decodeMs = Int((ContinuousClock.now - decodeStart).components.attoseconds / 1_000_000_000_000_000)

            cachedTailText = tailResult.text
            cachedTailSampleCount = simulatedSampleCount
            lastTailDecodeTime = ContinuousClock.now
            totalDecodeMs += decodeMs
            decodeCount += 1

            if verbose {
                print("    Tail decode: \(tailSamples.count) samples, \(decodeMs)ms, tail=\(tailResult.text.prefix(40))...")
            }
        }
    }

    // --- STOP: simulate handleStop() ---

    let deltaCount = totalSamples - lastDecodedSampleCount
    let deltaSeconds = Double(deltaCount) / Double(sampleRate)

    // Check Partial-Accept (Ansatz B)
    if partialAccept > 0 && deltaSeconds < partialAccept {
        // Use cached tail if available, otherwise accumulated text
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
    if tailInterval > 0 && !cachedTailText.isEmpty {
        let newSinceTail = totalSamples - cachedTailSampleCount
        let newSinceTailSeconds = Double(newSinceTail) / Double(sampleRate)
        if partialAccept > 0 && newSinceTailSeconds < partialAccept {
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
        let decodeMs = Int((ContinuousClock.now - decodeStart).components.attoseconds / 1_000_000_000_000_000)

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
        // Delta too small
        return StreamWhisperSimResult(
            text: accumulatedText,
            streamWaitMs: 0,
            totalDecodeMs: totalDecodeMs,
            decodeCount: decodeCount,
            deltaSeconds: deltaSeconds,
            usedPartial: true
        )
    } else {
        // No VAD decode happened — full decode
        var normalizedSamples = samples
        AudioProcessingUtils.peakNormalize(&normalizedSamples)

        let decodeStart = ContinuousClock.now
        let result = try await backend.transcribe(
            samples: normalizedSamples,
            language: language,
            prompt: ""
        )
        let decodeMs = Int((ContinuousClock.now - decodeStart).components.attoseconds / 1_000_000_000_000_000)

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
```

- [ ] **Step 2: runStreamWhisperMode Funktion hinzufuegen**

Am Anfang derselben Datei, vor simulateWhisperStream:

```swift
func runStreamWhisperMode(args: StreamWhisperArgs) async throws {
    let audioPath = args.audioPath
    let (samples, duration) = try loadAudio(path: audioPath)

    print("Audio:           \(audioPath) (\(String(format: "%.1f", duration))s)")
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
    let baseName = (audioPath as NSString).deletingPathExtension
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
        file: (audioPath as NSString).lastPathComponent,
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
```

- [ ] **Step 3: Kompilierung pruefen**

Run: `swift build --target WhisperCppTestCLI 2>&1 | tail -5`
Expected: Build-Fehler wegen fehlender StreamWhisperArgs und main.swift Einbindung (wird in Task 3 behoben).

- [ ] **Step 4: Commit**

```bash
git add Tools/WhisperCppTestCLI/Commands/StreamWhisperCommand.swift
git commit -m "feat(#36): stream-whisper Simulationskern (WhisperTranscriptionEngine-Nachbildung)"
```

---

### Task 3: CLI-Integration — Args und main.swift

**Files:**
- Modify: `Tools/WhisperCppTestCLI/CLIArguments.swift`
- Modify: `Tools/WhisperCppTestCLI/main.swift`

- [ ] **Step 1: StreamWhisperArgs hinzufuegen**

In `CLIArguments.swift` nach SweepArgs (Zeile 29):

```swift
struct StreamWhisperArgs {
    let audioPath: String
    let language: String?
    let modelName: String
    let fallbackInterval: Double
    let tailInterval: Double
    let partialAccept: Double
    let json: Bool
    let coreml: Bool
}

struct SweepWhisperArgs {
    let directory: String
    let language: String?
    let modelName: String
    let json: Bool
    let coreml: Bool
}
```

- [ ] **Step 2: Parse-Funktionen hinzufuegen**

Am Ende von CLIArguments.swift:

```swift
func parseStreamWhisperArgs() -> StreamWhisperArgs {
    let args = CommandLine.arguments
    let path = args.count > 2 ? args[2] : ""
    guard !path.isEmpty else {
        print("Fehler: Audio-Pfad erforderlich.")
        print("Usage: swift run WhisperCppTestCLI stream-whisper <audio-path> [de|en|auto] [--model large-v3_turbo] [--fallback-interval 4.0] [--tail-interval 0] [--partial-accept 0] [--json] [--coreml]")
        exit(1)
    }

    let langArg: String
    if args.count > 3, !args[3].hasPrefix("--") {
        langArg = args[3]
    } else {
        langArg = "de"
    }
    let flagStart = args.count > 3 && !args[3].hasPrefix("--") ? 4 : 3
    let flags = parseFlags(from: flagStart)

    return StreamWhisperArgs(
        audioPath: path,
        language: resolveLanguage(langArg),
        modelName: flags["model"] ?? "large-v3_turbo",
        fallbackInterval: Double(flags["fallback-interval"] ?? "") ?? 4.0,
        tailInterval: Double(flags["tail-interval"] ?? "") ?? 0,
        partialAccept: Double(flags["partial-accept"] ?? "") ?? 0,
        json: flags["json"] != nil,
        coreml: flags["coreml"] != nil
    )
}

func parseSweepWhisperArgs() -> SweepWhisperArgs {
    let args = CommandLine.arguments
    let dir = args.count > 2 ? args[2] : ""
    guard !dir.isEmpty else {
        print("Fehler: Verzeichnis-Pfad erforderlich.")
        print("Usage: swift run WhisperCppTestCLI sweep-whisper <directory> [de|en|auto] [--model large-v3_turbo] [--json] [--coreml]")
        exit(1)
    }

    let langArg: String
    if args.count > 3, !args[3].hasPrefix("--") {
        langArg = args[3]
    } else {
        langArg = "de"
    }
    let flagStart = args.count > 3 && !args[3].hasPrefix("--") ? 4 : 3
    let flags = parseFlags(from: flagStart)

    return SweepWhisperArgs(
        directory: dir,
        language: resolveLanguage(langArg),
        modelName: flags["model"] ?? "large-v3_turbo",
        json: flags["json"] != nil,
        coreml: flags["coreml"] != nil
    )
}
```

- [ ] **Step 3: main.swift erweitern**

In main.swift, Usage-String erweitern und Cases hinzufuegen:

Usage (nach Zeile 10):
```
  swift run WhisperCppTestCLI stream-whisper <audio-path> [de|en|auto] [--model large-v3_turbo] [--fallback-interval 4.0] [--tail-interval 0] [--partial-accept 0] [--json] [--coreml]
  swift run WhisperCppTestCLI sweep-whisper <directory> [de|en|auto] [--model large-v3_turbo] [--json] [--coreml]
```

Switch-Cases (nach Zeile 40):
```swift
        case "stream-whisper":
            let args = parseStreamWhisperArgs()
            try await runStreamWhisperMode(args: args)

        case "sweep-whisper":
            let args = parseSweepWhisperArgs()
            try await runSweepWhisperMode(args: args)
```

- [ ] **Step 4: Kompilierung pruefen**

Run: `swift build --target WhisperCppTestCLI 2>&1 | tail -5`
Expected: Fehler wegen `runSweepWhisperMode` (wird in Task 4 implementiert). `runStreamWhisperMode` und Types sollten kompilieren.

- [ ] **Step 5: Commit**

```bash
git add Tools/WhisperCppTestCLI/CLIArguments.swift Tools/WhisperCppTestCLI/main.swift
git commit -m "feat(#36): stream-whisper und sweep-whisper CLI-Integration"
```

---

### Task 4: sweep-whisper Command

**Files:**
- Create: `Tools/WhisperCppTestCLI/Commands/SweepWhisperCommand.swift`

- [ ] **Step 1: SweepWhisperCommand.swift erstellen**

Create `Tools/WhisperCppTestCLI/Commands/SweepWhisperCommand.swift`:

```swift
import Foundation
import DerFluisterer
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
        let (samples, _) = try loadAudio(path: path)
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
            let line = "\(e.params.fallbackInterval)".padding(toLength: 6, withPad: " ", startingAt: 0)
                + "\(e.params.tailInterval)".padding(toLength: 6, withPad: " ", startingAt: 0)
                + "\(e.params.partialAccept)".padding(toLength: 6, withPad: " ", startingAt: 0)
                + "\(String(format: "%.1f%%", e.avgWER * 100))".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "\(e.avgStreamWaitMs)".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "\(e.avgTotalDecodeMs)".padding(toLength: 8, withPad: " ", startingAt: 0)
                + (e.paretoOptimal ? " *" : "")
            print(line)
        }
    }
}
```

- [ ] **Step 2: Kompilierung pruefen**

Run: `swift build --target WhisperCppTestCLI 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Smoke Test stream-whisper**

Run: `swift run WhisperCppTestCLI stream-whisper Tests/Testdaten/Testaufnahme1.m4a de --model large-v3_turbo --coreml`

Expected: Lädt Modell, simuliert Streaming, gibt Ergebnis mit StreamWait, Decode-Count etc. aus.

- [ ] **Step 4: Commit**

```bash
git add Tools/WhisperCppTestCLI/Commands/SweepWhisperCommand.swift
git commit -m "feat(#36): sweep-whisper Parameter-Grid mit Pareto-Analyse"
```

---

### Task 5: Sweep durchfuehren und auswerten

**Files:** None (Ausfuehrung)

- [ ] **Step 1: Sweep starten**

Run: `swift run WhisperCppTestCLI sweep-whisper Tests/Testdaten de --model large-v3_turbo --coreml --json 2>/dev/null | tee Tests/Testdaten/streamwait-sweep.json`

Expected: ~30 Konfigurationen x 9 Audiodateien (ohne stille). Laufzeit ~30-50 Minuten.

- [ ] **Step 2: Ergebnisse analysieren**

Aus dem JSON/Tabellen-Output:
- Pareto-optimale Konfigurationen identifizieren
- Baseline (fb=4.0, tail=0, pa=0) als Vergleich
- Beste Konfiguration: niedrigste StreamWait bei akzeptabler WER

- [ ] **Step 3: Commit**

```bash
git add Tests/Testdaten/streamwait-sweep.json
git commit -m "test(#36): StreamWait Parameter Sweep Ergebnisse"
```
