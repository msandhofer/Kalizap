@preconcurrency import AVFoundation
import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - Live Mode

func runLiveMode(language: String?) async throws {
    print("=== SpeechSwiftTestCLI — Live Mode ===")
    print("Sprache: \(language)")
    print("")

    // 1. Load models (einmalig)
    let (asrModel, _) = try await loadASRModel()
    let (vadModel, _) = try await loadVADModel()

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

        // Setup mic capture
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let sampleBuffer = SampleBuffer()

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
        print("  Aufnahme läuft... Drücke Enter zum Stoppen.")

        _ = readLine()

        // Stop recording
        _ = ContinuousClock.now - recordStart
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

        if segments.isEmpty {
            print("  [VAD] Keine Sprache erkannt, überspringe Transkription.")
            continue
        }

        // Transcribe
        let transcribeStart = ContinuousClock.now
        let text = asrModel.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language
        )
        let transcribeTime = ContinuousClock.now - transcribeStart

        let transcribeMs = Double(transcribeTime.components.seconds * 1000)
            + Double(transcribeTime.components.attoseconds) / 1_000_000_000_000_000.0
        let rtf = audioDuration > 0 ? transcribeMs / (audioDuration * 1000.0) : 0

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
