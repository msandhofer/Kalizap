# SpeechSwiftTestCLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CLI-Prototyp der speech-swift (Qwen3-ASR) Transkription testet — Datei-Modus, Live Push-to-Talk, und Batch-Vergleich mit erwarteten Texten — inklusive Per-Stage-Latenz-Messung.

**Architecture:** Eigenständiges CLI-Target `SpeechSwiftTestCLI` in `Tools/`, ohne Dependency auf `DerFluisterer`. Nutzt `Qwen3ASR` und `SpeechVAD` von speech-swift direkt. Audio-Loading via AVFoundation (bewährtes Pattern aus WhisperCppTestCLI), Mic-Capture via AVAudioEngine.

**Tech Stack:** Swift 6.1, speech-swift (Qwen3Speech package), AVFoundation, ContinuousClock

---

## File Structure

| Datei | Verantwortung |
|-------|---------------|
| `Package.swift` | Modify: speech-swift Dependency + SpeechSwiftTestCLI Target |
| `Tools/SpeechSwiftTestCLI/main.swift` | Create: Entry point, Argument-Parsing, alle drei Modi |
| `Tools/SpeechSwiftTestCLI/AudioLoader.swift` | Create: Audio-Datei laden + Resampling auf 16kHz |
| `Tools/SpeechSwiftTestCLI/SampleBuffer.swift` | Create: Thread-safe Sample-Collector für Mic-Capture |

---

## Task 1: Package-Setup + Kompilierung verifizieren

**Files:**
- Modify: `Package.swift`
- Create: `Tools/SpeechSwiftTestCLI/main.swift` (minimal)

- [ ] **Step 1: speech-swift Dependency zu Package.swift hinzufügen**

```swift
// In dependencies Array, nach Sparkle:
.package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
```

- [ ] **Step 2: SpeechSwiftTestCLI Target hinzufügen**

```swift
// In targets Array, nach WhisperCppTestCLI:
.executableTarget(
    name: "SpeechSwiftTestCLI",
    dependencies: [
        .product(name: "Qwen3ASR", package: "Qwen3Speech"),
        .product(name: "SpeechVAD", package: "Qwen3Speech"),
    ],
    path: "Tools/SpeechSwiftTestCLI"
),
```

Wichtig: Package-Name ist `"Qwen3Speech"` (nicht `"speech-swift"`).

- [ ] **Step 3: Minimales main.swift erstellen**

Datei: `Tools/SpeechSwiftTestCLI/main.swift`

```swift
import Foundation
import Qwen3ASR

print("=== SpeechSwiftTestCLI ===")
print("Qwen3ASR erfolgreich importiert.")
print("PASS")
```

- [ ] **Step 4: Kompilierung testen**

Run: `swift build --target SpeechSwiftTestCLI 2>&1 | tail -5`

Expected: Build erfolgreich ODER Metal-Shader-Fehler.

**Falls Metal-Shader-Fehler:** MLX-Swift braucht kompilierte Metal-Shader. Zwei Optionen:

Option A — Xcode Build:
```bash
xcodebuild -scheme SpeechSwiftTestCLI -configuration Debug build 2>&1 | tail -10
```

Option B — Manual Metal Shader Build:
```bash
# Pfad prüfen nach swift build:
find .build -name "*.metal" -path "*/mlx/*" | head -5
# Dann: scripts/build_mlx_metallib.sh aus speech-swift adaptieren
```

Falls keines funktioniert: in der Konversation mit dem User besprechen bevor weitergemacht wird.

- [ ] **Step 5: Binary ausführen**

```bash
swift run SpeechSwiftTestCLI
```

Expected output:
```
=== SpeechSwiftTestCLI ===
Qwen3ASR erfolgreich importiert.
PASS
```

- [ ] **Step 6: Commit**

```bash
git add Package.swift Tools/SpeechSwiftTestCLI/main.swift
git commit -m "feat: add SpeechSwiftTestCLI target with speech-swift dependency"
```

---

## Task 2: Audio-Loader erstellen

**Files:**
- Create: `Tools/SpeechSwiftTestCLI/AudioLoader.swift`

- [ ] **Step 1: AudioLoader.swift erstellen**

Datei: `Tools/SpeechSwiftTestCLI/AudioLoader.swift`

```swift
import AVFoundation

enum AudioLoader {
    /// Lädt eine Audio-Datei und konvertiert zu 16kHz Mono Float32.
    /// Unterstützt m4a, wav, mp3, caf und alle von AVAudioFile unterstützten Formate.
    static func loadSamples(from path: String) throws -> (samples: [Float], duration: Double) {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw AudioLoaderError.cannotCreateConverter
        }

        let frameCount = AVAudioFrameCount(
            Double(file.length) * 16000.0 / file.processingFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else {
            throw AudioLoaderError.cannotCreateBuffer
        }

        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            let remaining = file.length - file.framePosition
            guard remaining > 0 else {
                outStatus.pointee = .endOfStream
                return nil
            }
            let count = AVAudioFrameCount(min(remaining, 4096))
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: count
            ) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: inputBuffer)
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if let conversionError { throw conversionError }

        guard let channelData = outputBuffer.floatChannelData else {
            throw AudioLoaderError.noChannelData
        }

        let samples = Array(
            UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength))
        )
        let duration = Double(samples.count) / 16000.0
        return (samples, duration)
    }
}

enum AudioLoaderError: Error, CustomStringConvertible {
    case cannotCreateConverter
    case cannotCreateBuffer
    case noChannelData

    var description: String {
        switch self {
        case .cannotCreateConverter: "Audio-Converter konnte nicht erstellt werden"
        case .cannotCreateBuffer: "Audio-Buffer konnte nicht erstellt werden"
        case .noChannelData: "Keine Channel-Daten im Audio"
        }
    }
}
```

- [ ] **Step 2: Verifizieren dass es kompiliert**

Run: `swift build --target SpeechSwiftTestCLI 2>&1 | tail -3`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Tools/SpeechSwiftTestCLI/AudioLoader.swift
git commit -m "feat(SpeechSwiftTestCLI): add AudioLoader for file-based audio loading"
```

---

## Task 3: Datei-Transkription mit Per-Stage-Timing

**Files:**
- Modify: `Tools/SpeechSwiftTestCLI/main.swift`

- [ ] **Step 1: main.swift mit Datei-Transkription implementieren**

Datei: `Tools/SpeechSwiftTestCLI/main.swift` (komplett ersetzen)

```swift
import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - Configuration

let usage = """
Usage:
  swift run SpeechSwiftTestCLI file <audio-path> [de|en]
  swift run SpeechSwiftTestCLI live [de|en]
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
    let ms = duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
    return "\(ms)ms"
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

    // 5. Results
    let rtf = Double(transcribeTime.components.seconds * 1_000_000_000_000_000_000
        + transcribeTime.components.attoseconds)
        / (audioDuration * 1_000_000_000_000_000_000)

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
            print("Live-Modus noch nicht implementiert.")
            exit(1)

        case "batch":
            print("Batch-Modus noch nicht implementiert.")
            exit(1)

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
```

- [ ] **Step 2: Build**

Run: `swift build --target SpeechSwiftTestCLI`
Expected: Build succeeded

- [ ] **Step 3: Testen mit TestAudio.m4a**

Run: `swift run SpeechSwiftTestCLI file TestAudio.m4a de`

Expected: Modell wird heruntergeladen (erster Lauf ~680MB), dann Timing-Tabelle + transkribierter Text.

**Falls Metal-Shader-Fehler:** Siehe Task 1 Step 4 für Workarounds.

**Falls Modell-Download fehlschlägt:** HuggingFace-Erreichbarkeit prüfen, ggf. `QWEN3_CACHE_DIR` Environment-Variable setzen.

- [ ] **Step 4: Commit**

```bash
git add Tools/SpeechSwiftTestCLI/main.swift
git commit -m "feat(SpeechSwiftTestCLI): file transcription with per-stage timing"
```

---

## Task 4: SampleBuffer für Thread-safe Mic-Capture

**Files:**
- Create: `Tools/SpeechSwiftTestCLI/SampleBuffer.swift`

- [ ] **Step 1: SampleBuffer.swift erstellen**

Datei: `Tools/SpeechSwiftTestCLI/SampleBuffer.swift`

```swift
import Foundation

/// Thread-safe Audio-Sample-Collector für Mic-Capture.
/// Sammelt Float-Samples aus dem Audio-Thread und gibt sie gesammelt zurück.
final class SampleBuffer: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func reset() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
```

- [ ] **Step 2: Verifizieren dass es kompiliert**

Run: `swift build --target SpeechSwiftTestCLI 2>&1 | tail -3`
Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Tools/SpeechSwiftTestCLI/SampleBuffer.swift
git commit -m "feat(SpeechSwiftTestCLI): add thread-safe SampleBuffer for mic capture"
```

---

## Task 5: Live Push-to-Talk Modus

**Files:**
- Modify: `Tools/SpeechSwiftTestCLI/main.swift`

- [ ] **Step 1: Mic-Capture-Funktion und Live-Modus hinzufügen**

In `main.swift`, vor dem `// MARK: - Main` Block, folgende Funktion einfügen:

```swift
// MARK: - Live Mode

func runLiveMode(language: String) async throws {
    print("=== SpeechSwiftTestCLI — Live Mode ===")
    print("Sprache: \(language)")
    print("")

    // 1. Load models (einmalig)
    let (asrModel, modelLoadTime) = try await loadASRModel()
    let (vadModel, vadLoadTime) = try await loadVADModel()

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

        // Setup mic
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let sampleBuffer = SampleBuffer()

        // Target format: 16kHz mono Float32
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
        print("  🎙 Aufnahme läuft... Drücke Enter zum Stoppen.")

        _ = readLine()

        // Stop recording
        let recordTime = ContinuousClock.now - recordStart
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

        // Transcribe
        let transcribeStart = ContinuousClock.now
        let text = asrModel.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language
        )
        let transcribeTime = ContinuousClock.now - transcribeStart

        let rtf = audioDuration > 0
            ? Double(transcribeTime.components.seconds * 1_000_000_000_000_000_000
                + transcribeTime.components.attoseconds)
                / (audioDuration * 1_000_000_000_000_000_000)
            : 0

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
```

- [ ] **Step 2: AVFoundation Import hinzufügen**

Am Anfang von `main.swift`:

```swift
import AVFoundation
```

- [ ] **Step 3: Live-Modus in Main-Switch einbinden**

Den `case "live"` Block ersetzen:

```swift
case "live":
    let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "de"
    try await runLiveMode(language: language)
```

- [ ] **Step 4: Build**

Run: `swift build --target SpeechSwiftTestCLI 2>&1 | tail -3`
Expected: Build succeeded

- [ ] **Step 5: Live-Modus testen**

Run: `swift run SpeechSwiftTestCLI live de`

Expected:
1. Modelle werden geladen
2. "Drücke Enter zum Starten..." erscheint
3. Enter → Aufnahme läuft
4. Etwas diktieren, Enter → Timing + Text erscheint
5. Erneut Enter für nächste Aufnahme, 'q' zum Beenden

**Falls Mikrofon-Berechtigung fehlt:** In Systemeinstellungen → Datenschutz → Mikrofon die Terminal-App autorisieren.

- [ ] **Step 6: Commit**

```bash
git add Tools/SpeechSwiftTestCLI/main.swift
git commit -m "feat(SpeechSwiftTestCLI): add live push-to-talk mode with mic capture"
```

---

## Task 6: Batch-Modus mit Expected-Text-Vergleich

**Files:**
- Modify: `Tools/SpeechSwiftTestCLI/main.swift`

- [ ] **Step 1: Batch-Modus-Funktion hinzufügen**

In `main.swift`, vor dem `// MARK: - Main` Block, folgende Funktion einfügen:

```swift
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
    let (_, vadLoadTime) = try await loadVADModel()
    print("")

    // 3. Transcribe each file
    var results: [BatchResult] = []

    for (index, fileURL) in audioFiles.enumerated() {
        let fileName = fileURL.lastPathComponent
        print("[\(index + 1)/\(audioFiles.count)] \(fileName)")

        let (samples, audioDuration) = try AudioLoader.loadSamples(from: fileURL.path)

        let transcribeStart = ContinuousClock.now
        let text = asrModel.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language
        )
        let transcribeTime = ContinuousClock.now - transcribeStart
        let transcribeMs = transcribeTime.components.seconds * 1000
            + transcribeTime.components.attoseconds / 1_000_000_000_000_000
        let rtf = Double(transcribeMs) / (audioDuration * 1000)

        // Check for expected text
        let baseName = fileURL.deletingPathExtension().path
        let expectedPath = baseName + ".expected.txt"
        let expected: String? = fm.fileExists(atPath: expectedPath)
            ? try? String(contentsOfFile: expectedPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
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

    // 4. Summary
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
```

- [ ] **Step 2: Batch-Modus in Main-Switch einbinden**

Den `case "batch"` Block ersetzen:

```swift
case "batch":
    let dir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
    guard !dir.isEmpty else {
        print("Fehler: Verzeichnis-Pfad erforderlich.")
        print(usage)
        exit(1)
    }
    let language = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "de"
    try await runBatchMode(directory: dir, language: language)
```

- [ ] **Step 3: Build**

Run: `swift build --target SpeechSwiftTestCLI 2>&1 | tail -3`
Expected: Build succeeded

- [ ] **Step 4: Testen mit einzelner Datei**

Run: `swift run SpeechSwiftTestCLI batch . de`

(Nutzt das Projektverzeichnis, das `TestAudio.m4a` enthält.)

Expected: Tabelle mit einer Zeile für TestAudio.m4a.

- [ ] **Step 5: Commit**

```bash
git add Tools/SpeechSwiftTestCLI/main.swift
git commit -m "feat(SpeechSwiftTestCLI): add batch mode with expected-text comparison"
```

---

## Task 7 (Optional): Parakeet-TDT Support

**Voraussetzung:** Nur umsetzen, wenn ParakeetASR dieselbe `SpeechRecognitionModel`-Konformität hat wie Qwen3ASR. Vorab prüfen:

Run: `grep -r "SpeechRecognitionModel" .build/checkouts/speech-swift/Sources/ParakeetASR/ 2>/dev/null | head -5`

Falls ja → weiter. Falls nein → Task überspringen.

**Files:**
- Modify: `Package.swift` (ParakeetASR Dependency zum Target)
- Modify: `Tools/SpeechSwiftTestCLI/main.swift`

- [ ] **Step 1: ParakeetASR Dependency hinzufügen**

In `Package.swift`, zum `SpeechSwiftTestCLI` Target:

```swift
.executableTarget(
    name: "SpeechSwiftTestCLI",
    dependencies: [
        .product(name: "Qwen3ASR", package: "Qwen3Speech"),
        .product(name: "SpeechVAD", package: "Qwen3Speech"),
        .product(name: "ParakeetASR", package: "Qwen3Speech"),
    ],
    path: "Tools/SpeechSwiftTestCLI"
),
```

- [ ] **Step 2: Engine-Auswahl in main.swift**

Import hinzufügen:
```swift
import ParakeetASR
```

Usage-String aktualisieren:
```swift
let usage = """
Usage:
  swift run SpeechSwiftTestCLI file <audio-path> [de|en] [--engine qwen3|parakeet]
  swift run SpeechSwiftTestCLI live [de|en] [--engine qwen3|parakeet]
  swift run SpeechSwiftTestCLI batch <directory> [de|en] [--engine qwen3|parakeet]
"""
```

Engine-Argument parsen (nach `modelId` Definition):
```swift
let engineArg = CommandLine.arguments.first { $0.hasPrefix("--engine") }
    .flatMap { _ in CommandLine.arguments.drop { $0 != "--engine" }.dropFirst().first }
    ?? "qwen3"
```

`loadASRModel()` anpassen, um ein Protocol-Objekt zurückzugeben. Die genaue Implementierung hängt davon ab, ob `ParakeetASRModel` dasselbe `transcribe(audio:sampleRate:language:)` Interface hat. Falls ja, kann eine gemeinsame Closure oder ein Protocol-Wrapper genutzt werden. Falls die APIs zu unterschiedlich sind → Task abbrechen.

- [ ] **Step 3: Testen**

Run: `swift run SpeechSwiftTestCLI file TestAudio.m4a de --engine parakeet`
Expected: Transkription mit Parakeet-TDT + Timing

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tools/SpeechSwiftTestCLI/main.swift
git commit -m "feat(SpeechSwiftTestCLI): add optional Parakeet-TDT engine support"
```

---

## Risiken & Workarounds

| Risiko | Erkennung | Workaround |
|--------|-----------|------------|
| Metal-Shader-Fehler bei `swift build` | Runtime-Crash "Failed to load metallib" | Build via `xcodebuild` oder manueller Metal-Shader-Build |
| Modell-Download fehlschlägt | Timeout/Netzwerkfehler | HuggingFace-Token setzen, `HF_TOKEN` env var |
| Mic-Berechtigung fehlt | `AVAudioEngine.start()` wirft | Terminal in Systemeinstellungen → Mikrofon autorisieren |
| speech-swift API-Änderung (pre-1.0) | Kompilierungsfehler | `branch: "main"` auf konkreten Commit pinnen |
| Qwen3-ASR Deutsch-Qualität ungenügend | Batch-Test zeigt hohe Abweichung | Alternatives Modell testen (1.7B, 8-bit) |

## Testdateien-Konvention

Der User legt folgende Dateien an:

```
TestAudio/
  test1_kurz.m4a           # ~2s Diktat
  test1_kurz.expected.txt   # Erwarteter Text
  test2_mittel.m4a          # ~5s Diktat
  test2_mittel.expected.txt
  test3_lang.m4a            # ~10s Diktat
  test3_lang.expected.txt
  test4_englisch.m4a        # ~5s Englisch
  test4_englisch.expected.txt
  test5_gemischt.m4a        # ~5s Deutsch-Englisch gemischt
  test5_gemischt.expected.txt
```

Batch-Test: `swift run SpeechSwiftTestCLI batch TestAudio/ de`
