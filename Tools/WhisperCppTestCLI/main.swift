import Foundation
import AVFoundation
import DerFluisterer

// MARK: - Configuration

let modelName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tiny"
let audioPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "TestAudio.m4a"

print("=== WhisperCppTestCLI ===")
print("Modell:  \(modelName)")
print("Audio:   \(audioPath)")
print("")

// MARK: - Audio Loading

func loadAudioSamples(from path: String) throws -> [Float] {
    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)

    let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
        throw NSError(domain: "WhisperCppTestCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
    }

    let frameCount = AVAudioFrameCount(Double(file.length) * 16000.0 / file.processingFormat.sampleRate)
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
        throw NSError(domain: "WhisperCppTestCLI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create output buffer"])
    }

    var error: NSError?
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
        let inputFrameCount = min(file.length - file.framePosition, Int64(4096))
        guard inputFrameCount > 0 else {
            outStatus.pointee = .endOfStream
            return nil
        }
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(inputFrameCount)) else {
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

    if let error { throw error }

    guard let channelData = outputBuffer.floatChannelData else {
        throw NSError(domain: "WhisperCppTestCLI", code: 3, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
    }

    return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
}

// MARK: - Test

Task {
    let totalStart = ContinuousClock.now

    do {
        // 1. Load model
        print("--- Lade Modell via WhisperCppBackend ---")
        let loadStart = ContinuousClock.now
        let backend = WhisperCppBackend(model: modelName)
        try await backend.loadModel(for: .german) { progress in
            print("  Progress: \(Int(progress * 100))%")
        }
        let loadTime = ContinuousClock.now - loadStart
        print("Modell geladen in \(loadTime)")

        // 2. Load audio
        print("\n--- Lade Audio ---")
        let samples = try loadAudioSamples(from: audioPath)
        let durationSeconds = Double(samples.count) / 16000.0
        print("Audio: \(samples.count) samples (\(String(format: "%.1f", durationSeconds))s)")

        // 3. Transcribe
        print("\n--- Transkribiere ---")
        let transcribeStart = ContinuousClock.now
        let result = try await backend.transcribe(samples: samples, language: "de", prompt: "")
        let transcribeTime = ContinuousClock.now - transcribeStart
        print("Text: \(result.text)")
        print("Transkription in \(transcribeTime)")
        print("Segmente: \(result.segments.count)")

        // 4. Summary
        let totalTime = ContinuousClock.now - totalStart
        print("\n=== Zusammenfassung ===")
        print("Modell laden:    \(loadTime)")
        print("Transkription:   \(transcribeTime)")
        print("Gesamt:          \(totalTime)")
        print("Audio-Dauer:     \(String(format: "%.1f", durationSeconds))s")
        print("Realtime-Faktor: \(String(format: "%.2f", Double(transcribeTime.components.seconds) / durationSeconds))x")
        print("\nPASS")

    } catch {
        let elapsed = ContinuousClock.now - totalStart
        print("\nFEHLER nach \(elapsed):")
        print("  Typ:  \(type(of: error))")
        print("  Desc: \(error)")
    }

    exit(0)
}

RunLoop.main.run()
