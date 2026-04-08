import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - Constants

let modelId = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"

// MARK: - Language Resolution

/// Maps language argument to API parameter. "auto" → nil (auto-detect, supports code-switching).
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
