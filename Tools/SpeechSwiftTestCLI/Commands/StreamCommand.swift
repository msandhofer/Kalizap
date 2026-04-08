@preconcurrency import AVFoundation
import Foundation
import Qwen3ASR
import SpeechVAD

// MARK: - Stream State

/// Mutable state shared between the VAD background task and the main recording loop.
/// Declared @unchecked Sendable because access is serialised by design:
/// the Task reads/writes during recording, the outer function reads after cancellation.
final class StreamState: @unchecked Sendable {
    var vadCursor: Int = 0
    var segmentTexts: [(text: String, sttDuration: Duration, startTime: Float, endTime: Float)] = []
    var currentSpeechStartTime: Float? = nil  // Track ongoing speech for force-split
    var lastTranscribedEnd: Float = 0  // Prevents double-transcription after force-split
    var pendingAudioStart: Float? = nil  // Accumulate short segments until minSegmentDuration reached

    /// Transcribe a segment and append to results. Context only for segments > 1s to avoid hallucination.
    func transcribeAndAppend(
        audio: [Float], startTime: Float, endTime: Float,
        model: Qwen3ASRModel, language: String?, label: String
    ) {
        let segmentDuration = endTime - startTime
        // Only pass context for segments > 1s — very short segments hallucinate with long context
        let context: String? = segmentDuration > 1.0 ? segmentTexts.last?.text : nil

        let sttStart = ContinuousClock.now
        let text = model.transcribe(
            audio: audio,
            sampleRate: 16000,
            language: language,
            context: context
        )
        let sttTime = ContinuousClock.now - sttStart

        segmentTexts.append((text: text, sttDuration: sttTime, startTime: startTime, endTime: endTime))
        lastTranscribedEnd = endTime
        print("  [Segment \(segmentTexts.count)] \"\(text)\" (\(label)\(String(format: "%.1f", startTime))-\(String(format: "%.1f", endTime))s, STT: \(formatMs(sttTime)))")
    }
}

// MARK: - Stream Mode

func runStreamMode(language: String?) async throws {
    print("=== SpeechSwiftTestCLI — Stream Mode ===")
    print("Sprache: \(language)")
    print("Real-time VAD + Segment-Transkription")
    print("")

    // 1. Load models
    let (asrModel, _) = try await loadASRModel()
    let (vadModel, _) = try await loadVADModel()
    let vadConfig = VADConfig(
        onset: 0.5,
        offset: 0.35,
        minSpeechDuration: 0.25,
        minSilenceDuration: 0.4,   // 400ms — Kompromiss: Atempausen ignorieren, Sprechpausen erkennen
        windowDuration: 0.032,
        stepRatio: 1.0
    )
    let processor = StreamingVADProcessor(model: vadModel, config: vadConfig)
    let maxSegmentSeconds: Float = 7.0   // Force-Split nach 7s — STT ~655ms, gute Qualität
    let minSegmentSeconds: Float = 3.0   // Segmente < 3s nicht einzeln transkribieren

    print("\nBereit. (minSilence: \(vadConfig.minSilenceDuration)s, minSegment: \(minSegmentSeconds)s, maxSegment: \(maxSegmentSeconds)s)")
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

        // Setup mic capture (same as live mode)
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
                let newSamples = Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(convertedBuffer.frameLength)
                    )
                )
                sampleBuffer.append(newSamples)
            }
        }

        // Start recording
        engine.prepare()
        try engine.start()
        print("  Aufnahme läuft... Drücke Enter zum Stoppen.")
        print("")

        // Streaming state (in a Sendable container so the Task can capture it)
        processor.reset()
        let state = StreamState()

        // Background VAD + transcription task
        // Use nonisolated(unsafe) to pass non-Sendable models to the task
        nonisolated(unsafe) let asrRef = asrModel
        nonisolated(unsafe) let processorRef = processor

        let vadTask = Task {
            while !Task.isCancelled {
                let newSamples = sampleBuffer.samples(from: state.vadCursor)
                if !newSamples.isEmpty {
                    state.vadCursor += newSamples.count

                    let events = processorRef.process(samples: newSamples)

                    for event in events {
                        switch event {
                        case .speechStarted(let time):
                            state.currentSpeechStartTime = time
                            print("  [VAD \(String(format: "%.1f", time))s] Sprache erkannt")
                        case .speechEnded(let segment):
                            state.currentSpeechStartTime = nil
                            let effectiveStart = max(segment.startTime, state.lastTranscribedEnd)
                            let segmentDuration = segment.endTime - effectiveStart
                            guard segmentDuration > 0.1 else { continue }

                            // Accumulate start from pending or this segment
                            let accumulatedStart = state.pendingAudioStart ?? effectiveStart

                            if (segment.endTime - accumulatedStart) < minSegmentSeconds {
                                // Too short — defer, will be merged with next segment or flushed at stop
                                if state.pendingAudioStart == nil {
                                    state.pendingAudioStart = accumulatedStart
                                }
                                print("  [VAD \(String(format: "%.1f", segment.endTime))s] Segment zu kurz (\(String(format: "%.1f", segment.endTime - accumulatedStart))s), sammle weiter")
                                continue
                            }

                            // Long enough — transcribe from accumulated start
                            state.pendingAudioStart = nil
                            let allSamples = sampleBuffer.samples
                            let startIdx = max(0, Int(accumulatedStart * 16000))
                            let endIdx = min(Int(segment.endTime * 16000), allSamples.count)
                            guard endIdx - startIdx > 1600 else { continue }
                            let segmentAudio = Array(allSamples[startIdx..<endIdx])

                            state.transcribeAndAppend(
                                audio: segmentAudio, startTime: accumulatedStart, endTime: segment.endTime,
                                model: asrRef, language: language, label: ""
                            )
                        }
                    }

                    // Force-split: if untranscribed audio exceeds maxSegmentSeconds
                    if let speechStart = state.currentSpeechStartTime {
                        let effectiveStart = state.pendingAudioStart ?? max(speechStart, state.lastTranscribedEnd)
                        let currentTime = Float(state.vadCursor) / 16000.0
                        let untranscribedDuration = currentTime - effectiveStart
                        if untranscribedDuration >= maxSegmentSeconds {
                            let allSamples = sampleBuffer.samples
                            let startIdx = max(0, Int(effectiveStart * 16000))
                            let endIdx = allSamples.count
                            guard endIdx - startIdx > 1600 else { continue }
                            let segmentAudio = Array(allSamples[startIdx..<endIdx])

                            state.pendingAudioStart = nil
                            state.transcribeAndAppend(
                                audio: segmentAudio, startTime: effectiveStart, endTime: currentTime,
                                model: asrRef, language: language, label: "force-split, "
                            )

                            state.currentSpeechStartTime = currentTime
                        }
                    }
                }

                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break // Cancelled
                }
            }
        }

        // Wait for Enter to stop
        _ = readLine()
        let stopTime = ContinuousClock.now

        // Stop recording
        engine.stop()
        inputNode.removeTap(onBus: 0)
        vadTask.cancel()

        // Small delay to let the task clean up
        try await Task.sleep(for: .milliseconds(50))

        // Process remaining audio through VAD + flush
        let remainingSamples = sampleBuffer.samples(from: state.vadCursor)
        if !remainingSamples.isEmpty {
            _ = processor.process(samples: remainingSamples)
        }
        let flushEvents = processor.flush()

        // At stop: transcribe everything from lastTranscribedEnd (or pendingAudioStart) to end
        // No minSegment restriction — flush everything
        let finalStart = state.pendingAudioStart ?? state.lastTranscribedEnd
        let allSamplesForFlush = sampleBuffer.samples
        let audioDurationTotal = Float(allSamplesForFlush.count) / 16000.0

        if finalStart < audioDurationTotal - 0.1 {
            let startIdx = max(0, Int(finalStart * 16000))
            let endIdx = allSamplesForFlush.count
            if endIdx - startIdx > 1600 {
                let segmentAudio = Array(allSamplesForFlush[startIdx..<endIdx])
                state.pendingAudioStart = nil
                state.transcribeAndAppend(
                    audio: segmentAudio, startTime: finalStart, endTime: audioDurationTotal,
                    model: asrModel, language: language, label: "flush, "
                )
            }
        }

        let afterStreamTime = ContinuousClock.now

        // Total audio
        let allSamples = sampleBuffer.samples
        let audioDuration = Double(allSamples.count) / 16000.0

        guard !state.segmentTexts.isEmpty else {
            print("\n  [VAD] Keine Sprache erkannt.")
            continue
        }

        // Streaming results
        let streamText = state.segmentTexts.map(\.text).joined(separator: " ")
        let lastSegmentSTT = state.segmentTexts.last!.sttDuration
        let totalSTT = state.segmentTexts.reduce(Duration.zero) { $0 + $1.sttDuration }
        let preTranscribed = state.segmentTexts.count - 1 // segments transcribed during recording
        let latencyAfterStop = afterStreamTime - stopTime

        // Timing table
        printTimingTable([
            ("Aufnahme-Dauer", "\(String(format: "%.1f", audioDuration))s"),
            ("Segmente", "\(state.segmentTexts.count)"),
            ("Voraus-transkribiert", "\(max(0, preTranscribed)) (während Aufnahme)"),
            ("Letztes Segment STT", formatMs(lastSegmentSTT)),
            ("Latenz nach Stop", formatMs(latencyAfterStop)),
            ("Gesamt-STT", "\(formatMs(totalSTT)) (alle Segmente)"),
        ])

        print("  Stream-Text: \(streamText)")
    }
}
