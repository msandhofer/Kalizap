import Foundation
import DerFluisterer

print("=== TranscribeTestCLI ===")
print("Testet WhisperKit Batch-Transkription mit echtem Mikrofon.")
print("")

let recorder = AudioRecorderImpl()
let backend = WhisperKitBackend(model: "tiny")
let transcriber = BatchTranscriber(backend: backend)

Task {
    // 1. Load WhisperKit model
    print("Lade WhisperKit-Modell 'tiny' (~75MB)...")
    print("(verbose/debug ist aktiviert — du siehst WhisperKit-Logs)")
    print("")
    do {
        try await transcriber.loadModel(for: .german) { progress in
            print("  Modell-Fortschritt: \(Int(progress * 100))%")
        }
        print("✓ Modell geladen")
    } catch {
        print("✗ Modell-Laden fehlgeschlagen: \(error)")
        exit(1)
    }
    print("")

    // 2. Select default microphone
    do {
        try await recorder.selectDefaultDevice()
        print("✓ Mikrofon: \(recorder.selectedDevice?.name ?? "Default")")
    } catch {
        print("✗ Mikrofon-Fehler: \(error)")
        exit(1)
    }
    print("")

    // 3. Record for 5 seconds
    print("Starte 5-Sekunden-Aufnahme...")
    print("Sprich jetzt etwas auf Deutsch!")
    print("")

    do {
        try await recorder.startRecording()
    } catch {
        print("✗ Aufnahme-Fehler: \(error)")
        exit(1)
    }

    // Collect chunks in background
    var allChunks: [AudioChunk] = []
    let collectTask = Task {
        for try await chunk in recorder.audioStream {
            allChunks.append(chunk)
        }
    }

    // Wait 5 seconds
    try? await Task.sleep(for: .seconds(5))

    await recorder.stopRecording()
    try? await collectTask.value

    let totalSamples = allChunks.reduce(0) { $0 + $1.samples.count }
    let duration = Double(totalSamples) / 16000.0
    print("✓ Aufnahme beendet: \(allChunks.count) Chunks, \(String(format: "%.1f", duration))s, \(totalSamples) Samples")
    print("")

    // 4. Transcribe
    let allSamples = allChunks.flatMap { $0.samples }
    print("Transkribiere \(allSamples.count) Samples...")
    print("")

    let config = TranscriptionConfig(language: .de, initialPrompt: "")

    let buffer = CollectedAudioBuffer(
        samples: allSamples,
        sampleRate: 16000,
        totalDuration: duration
    )

    do {
        let result = try await transcriber.transcribe(buffer: buffer, config: config)
        print("")
        print("=== Ergebnis ===")
        print("  Text: \(result.text)")
        print("  Verarbeitungszeit: \(result.processingTime)")
        print("  Segmente: \(result.segments.count)")
        for (i, segment) in result.segments.enumerated() {
            print("    [\(i)] \(segment.text)")
        }
        print("")

        if result.text.isEmpty {
            print("✗ FAIL: Leeres Transkript")
            exit(1)
        } else {
            print("✓ PASS: Transkription erfolgreich")
            exit(0)
        }
    } catch {
        print("✗ Transkription fehlgeschlagen: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
