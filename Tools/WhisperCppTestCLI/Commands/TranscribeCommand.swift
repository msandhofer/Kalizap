import Foundation
import DerFluisterer

// MARK: - Transcribe Command (original mode)

func runTranscribeMode(modelName: String, audioPath: String) async throws {
    print("=== WhisperCppTestCLI — Transcribe ===")
    print("Modell:  \(modelName)")
    print("Audio:   \(audioPath)")
    print("")

    let totalStart = ContinuousClock.now

    // 1. Load model
    let (backend, loadTime) = try await loadWhisperCppModel(name: modelName, language: .german)

    // 2. Load audio
    print("\n--- Lade Audio ---")
    let (samples, durationSeconds) = try AudioLoader.loadSamples(from: audioPath)
    print("Audio: \(samples.count) samples (\(String(format: "%.1f", durationSeconds))s)")

    // 3. Transcribe
    print("\n--- Transkribiere ---")
    let transcribeStart = ContinuousClock.now
    let result = try await backend.transcribe(samples: samples, language: "de", prompt: "")
    let transcribeTime = ContinuousClock.now - transcribeStart
    print("Text: \(result.text)")
    print("Transkription in \(formatMs(transcribeTime))")
    print("Segmente: \(result.segments.count)")

    // 4. Summary
    let totalTime = ContinuousClock.now - totalStart
    printTimingTable([
        ("Modell laden", formatMs(loadTime)),
        ("Transkription", formatMs(transcribeTime)),
        ("Gesamt", formatMs(totalTime)),
        ("Audio-Dauer", "\(String(format: "%.1f", durationSeconds))s"),
        ("Realtime-Faktor", "\(String(format: "%.2f", Double(durationToMs(transcribeTime)) / (durationSeconds * 1000)))x"),
    ])

    print("PASS")
}
