import Foundation
import WhisperKit
import Kalizap

// MARK: - Configuration

let modelName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tiny"
let audioPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "TestAudio.m4a"
// Layer: "direct" = WhisperKit directly, "backend" = via WhisperKitBackend wrapper
let layer = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "direct"

print("=== WhisperModelTestCLI ===")
print("Modell:  \(modelName)")
print("Audio:   \(audioPath)")
print("Layer:   \(layer)")
print("")

// MARK: - Test

Task {
    let start = ContinuousClock.now

    do {
        switch layer {
        case "direct":
            print("--- Lade Modell direkt via WhisperKit ---")
            let config = WhisperKitConfig(
                model: modelName,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: true,
                logLevel: .debug
            )
            let whisperKit = try await WhisperKit(config)
            let elapsed = ContinuousClock.now - start
            print("✓ Modell geladen in \(elapsed)")

            print("\n--- Transkribiere ---")
            let results = try await whisperKit.transcribe(audioPath: audioPath)
            if let result = results.first {
                print("✓ Text: \(result.text)")
            }

        case "backend":
            print("--- Lade Modell via WhisperKitBackend ---")
            let backend = WhisperKitBackend(model: modelName)
            try await backend.loadModel(for: .german) { progress in
                print("  Progress: \(Int(progress * 100))%")
            }
            let elapsed = ContinuousClock.now - start
            print("✓ Modell geladen in \(elapsed)")

            print("\n--- Transkribiere via Backend ---")
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
            let result = try await backend.transcribe(samples: samples, language: "de", prompt: "")
            print("✓ Text: \(result.text)")

        case "pipeline":
            print("--- Lade Modell via Pipeline-ähnlichem Setup ---")
            print("(WhisperKitBackend + SimulatedProgress + Task.detached)")
            let backend = WhisperKitBackend(model: modelName)
            let engine = WhisperTranscriptionEngine(backend: backend)

            let estimatedDuration = Duration.seconds(60.0)
            let simulated = SimulatedProgress(estimatedDuration: estimatedDuration)

            let progressTask = Task.detached { @Sendable in
                for await progress in simulated.values {
                    print("  Simulated progress: \(Int(progress * 100))%")
                }
            }

            try await engine.loadModel(for: .german) { _ in }
            simulated.complete()
            await progressTask.value

            let elapsed = ContinuousClock.now - start
            print("✓ Modell geladen in \(elapsed)")

            print("\n--- Transkribiere via Engine ---")
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
            let result = try await backend.transcribe(samples: samples, language: "de", prompt: "")
            print("✓ Text: \(result.text)")

        case "mainactor":
            print("--- Lade Modell via Pipeline-Setup auf @MainActor ---")
            await MainActor.run {
                print("  Läuft auf MainActor: \(Thread.isMainThread)")
            }
            let backend2 = WhisperKitBackend(model: modelName)
            let engine2 = WhisperTranscriptionEngine(backend: backend2)

            let estimatedDuration2 = Duration.seconds(60.0)
            let simulated2 = SimulatedProgress(estimatedDuration: estimatedDuration2)

            let progressTask2 = Task.detached { @Sendable in
                for await progress in simulated2.values {
                    await MainActor.run {
                        print("  Simulated progress: \(Int(progress * 100))%")
                    }
                }
            }

            try await MainActor.run {
                // This is what the app does — loadModel called from @MainActor context
            }
            try await engine2.loadModel(for: .german) { _ in }
            simulated2.complete()
            await progressTask2.value

            let elapsed4 = ContinuousClock.now - start
            print("✓ Modell geladen in \(elapsed4)")

            print("\n--- Transkribiere ---")
            let samples2 = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
            let result2 = try await backend2.transcribe(samples: samples2, language: "de", prompt: "")
            print("✓ Text: \(result2.text)")

        default:
            print("✗ Unbekannter Layer: \(layer). Optionen: direct, backend, pipeline, mainactor")
            exit(1)
        }

        print("\n✓ PASS")

    } catch {
        let elapsed = ContinuousClock.now - start
        print("\n✗ FEHLER nach \(elapsed):")
        print("  Typ:  \(type(of: error))")
        print("  Desc: \(error)")
    }

    exit(0)
}

RunLoop.main.run()
