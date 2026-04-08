import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - File Mode

func runFileMode(path: String, language: String?) async throws {
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
