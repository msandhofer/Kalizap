import AVFoundation
import Foundation
import Speech
import STTTestCommon

// MARK: - Transcribe Command (offline, single file)

@available(macOS 26, *)
func runTranscribeMode(args: TranscribeArgs) async throws {
    let locale = resolveLocale(args.locale)

    print("=== SpeechAnalyzerTestCLI — Transcribe ===")
    print("Audio:   \(args.audioPath)")
    print("Locale:  \(locale.identifier)")
    print("")

    let totalStart = ContinuousClock.now

    // 1. Setup transcriber + ensure locale installed
    let transcriber = createTranscriber(locale: locale, preset: .transcription)
    try await ensureLocaleInstalled(locale: locale, transcriber: transcriber)
    let setupTime = ContinuousClock.now - totalStart

    // 2. Load audio file
    let audioURL = URL(fileURLWithPath: args.audioPath)
    let audioFile = try AVAudioFile(forReading: audioURL)
    let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

    print("Audio: \(String(format: "%.1f", audioDuration))s")

    // 3. Transcribe
    print("\n--- Transkribiere ---")
    let transcribeStart = ContinuousClock.now

    let analyzer = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [transcriber],
        finishAfterFile: true
    )
    _ = analyzer  // Keep analyzer alive during result consumption

    var parts: [String] = []
    for try await result in transcriber.results {
        let part = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.isEmpty { parts.append(part) }
    }
    let text = parts.joined(separator: " ")
    let transcribeTime = ContinuousClock.now - transcribeStart

    print("Text: \(text)")

    // 4. Summary
    let totalTime = ContinuousClock.now - totalStart
    let rtf = Double(durationToMs(transcribeTime)) / (audioDuration * 1000)

    printTimingTable([
        ("Setup/Locale", formatMs(setupTime)),
        ("Transkription", formatMs(transcribeTime)),
        ("Gesamt", formatMs(totalTime)),
        ("Audio-Dauer", "\(String(format: "%.1f", audioDuration))s"),
        ("Realtime-Faktor", "\(String(format: "%.3f", rtf))x"),
    ])

    print("PASS")
}

// MARK: - Raw Transcribe (for batch subprocess, outputs only text)

@available(macOS 26, *)
func runTranscribeRawMode(args: TranscribeArgs) async throws {
    let locale = resolveLocale(args.locale)

    let transcriber = createTranscriber(locale: locale, preset: .transcription)
    let audioURL = URL(fileURLWithPath: args.audioPath)
    let audioFile = try AVAudioFile(forReading: audioURL)

    let analyzer = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [transcriber],
        finishAfterFile: true
    )
    _ = analyzer

    var parts: [String] = []
    for try await result in transcriber.results {
        let part = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.isEmpty { parts.append(part) }
    }

    print(parts.joined(separator: " "))
}
