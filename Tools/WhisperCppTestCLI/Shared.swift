import Foundation
import DerFluisterer
import SpeechVAD

// MARK: - Language Resolution

func resolveLanguage(_ arg: String) -> String? {
    arg == "auto" ? nil : arg
}

// MARK: - Timing Helpers

func formatMs(_ duration: Duration) -> String {
    let total = duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
    return "\(total)ms"
}

func durationToMs(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
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

func loadWhisperCppModel(name: String, language: TranscriptionLanguage, coreml: Bool = false) async throws -> (WhisperCppBackend, Duration) {
    print("Lade whisper.cpp Modell (\(name)\(coreml ? ", CoreML" : ""))...")
    let start = ContinuousClock.now
    let backend = WhisperCppBackend(model: name, useCoreML: coreml)
    try await backend.loadModel(for: language) { progress in
        let pct = Int(progress * 100)
        print("  \(pct)%")
    }
    let elapsed = ContinuousClock.now - start
    print("Modell geladen in \(formatMs(elapsed))")
    return (backend, elapsed)
}

func loadVADModel() async throws -> (SileroVADModel, Duration) {
    print("Lade Silero VAD (CoreML)...")
    let start = ContinuousClock.now
    let vad = try await SileroVADModel.fromPretrained(engine: .coreml)
    let elapsed = ContinuousClock.now - start
    print("VAD geladen in \(formatMs(elapsed))")
    return (vad, elapsed)
}
