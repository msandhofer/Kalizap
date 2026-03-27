import Foundation
import AVFoundation
import Accelerate
import DerFluisterer
import CDeepFilter

print("=== VoiceProcessingTestCLI ===")
print("Testet DeepFilterNet3 Rauschunterdrückung mit Streaming-Processing.")
print("")

// MARK: - Accessibility Check

let checker = SystemAccessibilityChecker()
guard checker.isAccessibilityGranted() else {
    print("Accessibility-Permission fehlt!")
    print("  Systemeinstellungen -> Datenschutz -> Bedienungshilfen")
    _ = checker.requestAccessibility(prompt: true)
    exit(1)
}

// MARK: - DeepFilterNet3 Setup

print("Lade DeepFilterNet3 Modell...")

let sourceFile = URL(fileURLWithPath: #filePath)
let projectRoot = sourceFile
    .deletingLastPathComponent() // VoiceProcessingTestCLI
    .deletingLastPathComponent() // Tools
    .deletingLastPathComponent() // project root
let modelPath = projectRoot
    .appendingPathComponent("Sources/CDeepFilter/lib/DeepFilterNet3_onnx.tar.gz")
    .path

nonisolated(unsafe) let dfState: OpaquePointer = {
    guard let s = df_create(modelPath, 100.0, "warn") else {
        fatalError("DeepFilterNet3 konnte nicht initialisiert werden (Pfad: \(modelPath))")
    }
    return s
}()
let frameSize = Int(df_get_frame_length(dfState))
print("DeepFilterNet3 geladen (frameSize: \(frameSize) samples @ 48kHz = \(frameSize * 1000 / 48000)ms)")
print("")

// MARK: - Globals

nonisolated(unsafe) var isRecording = false
nonisolated(unsafe) var bypassEnabled = false
nonisolated(unsafe) var recordedSamples: [Float] = []       // Original-Audio
nonisolated(unsafe) var processedSamples: [Float] = []      // DeepFilterNet3-Audio
nonisolated(unsafe) var dfInputBuffer: [Float] = []          // Teilframe-Puffer fuer Streaming
nonisolated(unsafe) var totalSNR: Float = 0
nonisolated(unsafe) var frameCount: Int = 0
nonisolated(unsafe) let engine = AVAudioEngine()
let kSampleRate = 48000
let kTargetPeak: Float = 0.9

// MARK: - Peak Normalization

func peakNormalize(_ samples: inout [Float], targetPeak: Float = kTargetPeak) -> Float {
    guard !samples.isEmpty else { return 1.0 }
    var peak: Float = 0
    vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
    guard peak > 0.001 else { return 1.0 } // Stille nicht hochverstaerken
    let gain = targetPeak / peak
    vDSP_vsmul(samples, 1, [gain], &samples, 1, vDSP_Length(samples.count))
    return gain
}

// MARK: - Streaming DeepFilterNet3 Processing

/// Verarbeitet Samples durch DeepFilterNet3 Frame-by-Frame.
/// Haelt einen internen Puffer fuer Teilframes zwischen Callbacks.
func processStreamingChunk(_ input: [Float]) -> [Float] {
    dfInputBuffer.append(contentsOf: input)

    var output: [Float] = []
    output.reserveCapacity(dfInputBuffer.count)

    while dfInputBuffer.count >= frameSize {
        var inputFrame = Array(dfInputBuffer.prefix(frameSize))
        var outputFrame = [Float](repeating: 0, count: frameSize)

        if bypassEnabled {
            outputFrame = inputFrame
        } else {
            let snr = df_process_frame(dfState, &inputFrame, &outputFrame)
            totalSNR += snr
            frameCount += 1
        }

        output.append(contentsOf: outputFrame)
        dfInputBuffer.removeFirst(frameSize)
    }

    return output
}

// MARK: - Audio Playback

nonisolated(unsafe) var playbackEngine: AVAudioEngine?
nonisolated(unsafe) var playerNode: AVAudioPlayerNode?

func playAudio(_ samples: [Float], label: String) {
    guard !samples.isEmpty else {
        print("Keine Samples zum Abspielen.")
        return
    }

    playerNode?.stop()
    playbackEngine?.stop()

    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(kSampleRate),
        channels: 1,
        interleaved: false
    ) else { return }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
    }

    let pEngine = AVAudioEngine()
    let pNode = AVAudioPlayerNode()
    pEngine.attach(pNode)
    pEngine.connect(pNode, to: pEngine.mainMixerNode, format: format)
    playbackEngine = pEngine
    playerNode = pNode

    do {
        try pEngine.start()
        pNode.play()
        print("Wiedergabe [\(label)]...")

        let semaphore = DispatchSemaphore(value: 0)
        pNode.scheduleBuffer(buffer) {
            semaphore.signal()
        }

        DispatchQueue.global().async {
            semaphore.wait()
            pNode.stop()
            pEngine.stop()
            print("Wiedergabe beendet.")
            print("")
            printHelp()
        }
    } catch {
        print("FEHLER bei Wiedergabe: \(error)")
    }
}

// MARK: - Recording (Streaming)

func startRecording() {
    guard !isRecording else { return }
    recordedSamples = []
    processedSamples = []
    dfInputBuffer = []
    totalSNR = 0
    frameCount = 0
    isRecording = true

    let inputNode = engine.inputNode
    let hwFormat = inputNode.outputFormat(forBus: 0)

    guard let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(kSampleRate),
        channels: 1,
        interleaved: false
    ) else {
        print("FEHLER: Target-Format konnte nicht erstellt werden.")
        return
    }

    guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
        print("FEHLER: Audio-Converter konnte nicht erstellt werden.")
        return
    }

    inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * Double(kSampleRate) / buffer.format.sampleRate)
        ) else { return }

        var error: NSError?
        nonisolated(unsafe) var allConsumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if allConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            allConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, let channelData = convertedBuffer.floatChannelData else { return }
        let count = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        // Pegelanzeige
        let peak = samples.map { abs($0) }.max() ?? 0
        let barLen = min(Int(peak * 50), 50)
        let bar = String(repeating: "#", count: barLen) + String(repeating: ".", count: 50 - barLen)
        print("\r  [\(bar)] \(String(format: "%.3f", peak))", terminator: "")
        fflush(stdout)

        // Original-Audio behalten
        recordedSamples.append(contentsOf: samples)

        // Streaming: sofort durch DeepFilterNet3
        let processed = processStreamingChunk(samples)
        processedSamples.append(contentsOf: processed)
    }

    engine.prepare()
    do {
        try engine.start()
        print("Aufnahme + Streaming-Processing (48kHz)... Loslassen zum Stoppen.")
    } catch {
        print("FEHLER: Engine Start: \(error)")
        isRecording = false
    }
}

func stopRecording() {
    guard isRecording else { return }
    isRecording = false
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    print("")

    guard !processedSamples.isEmpty else {
        print("Zu wenig Audio aufgenommen.")
        return
    }

    let duration = Double(recordedSamples.count) / Double(kSampleRate)
    let avgSNR = frameCount > 0 ? totalSNR / Float(frameCount) : 0

    // Peak vorher
    var rawPeak: Float = 0
    vDSP_maxmgv(processedSamples, 1, &rawPeak, vDSP_Length(processedSamples.count))

    // Normalisierung
    let start = CFAbsoluteTimeGetCurrent()
    let gain = peakNormalize(&processedSamples)
    let normTime = (CFAbsoluteTimeGetCurrent() - start) * 1000

    print("Aufnahme gestoppt: \(String(format: "%.1f", duration))s, \(recordedSamples.count) Samples")
    print("")
    print("--- Streaming-Ergebnis ---")
    print("  Verarbeitung:    waehrend Aufnahme (0ms Zusatzlatenz)")
    print("  Frames:          \(frameCount)")
    print("  Avg SNR:         \(String(format: "%.1f", avgSNR)) dB")
    print("  Peak (roh):      \(String(format: "%.4f", rawPeak))")
    print("  Normalisierung:  Gain \(String(format: "%.1f", gain))x -> Peak \(String(format: "%.2f", kTargetPeak)) (\(String(format: "%.1f", normTime))ms)")
    print("--------------------------")

    // Wiedergabe
    if bypassEnabled {
        playAudio(recordedSamples, label: "BYPASS (Original)")
    } else {
        playAudio(processedSamples, label: "PROCESSED + NORMALIZED")
    }
}

// MARK: - Help

func printHelp() {
    let label = bypassEnabled ? "AN (Original)" : "AUS (DeepFilterNet3)"
    print("Steuerung:")
    print("  Rechte Option:  Halten = Aufnahme, Loslassen = Abspielen")
    print("  B:              Bypass-Toggle (aktuell: \(label))")
    print("  P:              Letzte Aufnahme erneut abspielen")
    print("  O:              Original (unverarbeitet) abspielen")
    print("  Ctrl+C:         Beenden")
    print("")
}

// MARK: - Hotkey Manager

nonisolated(unsafe) let hotkeyManager = HotkeyManagerImpl(configuration: .default)

Task {
    do {
        try await hotkeyManager.start()
        print("Hotkey-Manager aktiv (rechte Option-Taste)")
        print("")
        printHelp()

        for await event in hotkeyManager.events {
            switch event {
            case .recordingStarted:
                startRecording()
            case .recordingStopped:
                stopRecording()
            }
        }
    } catch {
        print("Hotkey-Fehler: \(error)")
        exit(1)
    }
}

// MARK: - Keyboard Input (B/P/O)

do {
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
}

DispatchQueue.global().async {
    let stdinFD = FileHandle.standardInput
    while true {
        let data = stdinFD.availableData
        guard let ch = String(data: data, encoding: .utf8)?.lowercased().first else { continue }
        switch ch {
        case "b":
            bypassEnabled.toggle()
            let label = bypassEnabled ? "AN (Original)" : "AUS (DeepFilterNet3)"
            print("\nBypass: \(label)\n")
        case "p":
            if bypassEnabled {
                playAudio(recordedSamples, label: "BYPASS (Original)")
            } else {
                playAudio(processedSamples, label: "PROCESSED + NORMALIZED")
            }
        case "o":
            print("\nSpiele Original...")
            playAudio(recordedSamples, label: "ORIGINAL (unverarbeitet)")
        default:
            break
        }
    }
}

RunLoop.main.run()
