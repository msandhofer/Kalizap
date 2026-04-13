import AVFoundation
import Foundation
import Speech

@available(macOS 26, *)
public final class SpeechAnalyzerTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private var locale: Locale = Locale(identifier: "de_DE")
    private var transcriptionTask: Task<Void, Never>?
    private var activeContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var continuationFinished = false

    private static let int16AudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(AudioProcessingUtils.transcriptionSampleRate),
        channels: 1,
        interleaved: true
    )!

    public init() {}

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        locale = language.locale

        // Verify locale is available, download if needed
        let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(locale) {
            onProgress(0.1)
            FileLog.log("SpeechAnalyzer — locale \(locale.identifier) not installed, downloading...")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                try await request.downloadAndInstall()
            }
            FileLog.log("SpeechAnalyzer — locale installed")
        }

        onProgress(1.0)
        FileLog.log("SpeechAnalyzer — ready for locale \(locale.identifier)")
    }

    public func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult> {
        cancel()

        let locale = self.locale

        return AsyncStream { continuation in
            self.activeContinuation = continuation
            self.continuationFinished = false

            self.transcriptionTask = Task { [weak self] in
                defer { self?.finishContinuation() }

                // Fresh transcriber per session to avoid worker-lock
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

                FileLog.log("SpeechAnalyzer — transcribe() started, locale=\(locale.identifier)")

                // Start the analyzer FIRST so it's ready to consume
                async let analyzerResult: CMTime? = analyzer.analyzeSequence(inputStream)

                // Sub-task A: Feed audio chunks to the analyzer
                let feederTask = Task {
                    var totalSamples: Int64 = 0
                    var chunkCount = 0
                    for await chunk in audioChunks {
                        guard !Task.isCancelled else { break }
                        guard let buffer = Self.convertToInt16Buffer(samples: chunk.samples) else { continue }
                        inputContinuation.yield(AnalyzerInput(buffer: buffer))
                        totalSamples += Int64(chunk.samples.count)
                        chunkCount += 1
                    }
                    inputContinuation.finish()
                    FileLog.log("SpeechAnalyzer — feeder done: \(chunkCount) chunks, \(totalSamples) samples")
                    return totalSamples
                }

                // Sub-task B: Consume results from the transcriber
                let resultTask = Task {
                    var accumulatedFinals = ""
                    var lastVolatileText = ""
                    let start = ContinuousClock.now
                    var volatileCount = 0

                    do {
                        for try await result in transcriber.results {
                            guard !Task.isCancelled else { break }
                            let text = String(result.text.characters)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }

                            if result.isFinal {
                                if accumulatedFinals.isEmpty {
                                    accumulatedFinals = text
                                } else {
                                    accumulatedFinals += " " + text
                                }
                                lastVolatileText = ""
                                continuation.yield(.partial(PartialTranscription(
                                    text: accumulatedFinals,
                                    confidence: 0
                                )))
                                FileLog.log("SpeechAnalyzer — final segment: \(text.prefix(60))")
                            } else {
                                volatileCount += 1
                                lastVolatileText = text
                                let displayText = accumulatedFinals.isEmpty
                                    ? text
                                    : accumulatedFinals + " " + text
                                continuation.yield(.partial(PartialTranscription(
                                    text: displayText,
                                    confidence: 0
                                )))
                            }
                        }
                    } catch {
                        FileLog.log("SpeechAnalyzer — result consumer error: \(error)")
                    }

                    let elapsed = ContinuousClock.now - start
                    let finalText = accumulatedFinals.isEmpty
                        ? lastVolatileText
                        : accumulatedFinals
                    FileLog.log("SpeechAnalyzer — results done: \(volatileCount) volatile, finalText=\(finalText.prefix(60))")
                    return (finalText, elapsed)
                }

                // Wait for audio feeding to finish
                let totalSamples = await feederTask.value
                guard !Task.isCancelled else {
                    FileLog.log("SpeechAnalyzer — cancelled after feeding")
                    await analyzer.cancelAndFinishNow()
                    return
                }

                // Finalize the analyzer
                do {
                    if let endTime = try await analyzerResult {
                        FileLog.log("SpeechAnalyzer — analyzeSequence returned \(endTime.seconds)s, finalizing...")
                        try await analyzer.finalizeAndFinish(through: endTime)
                    } else if totalSamples > 0 {
                        let endTime = CMTime(value: totalSamples, timescale: Int32(AudioProcessingUtils.transcriptionSampleRate))
                        FileLog.log("SpeechAnalyzer — no analyzerResult, using computed endTime \(endTime.seconds)s")
                        try await analyzer.finalizeAndFinish(through: endTime)
                    } else {
                        FileLog.log("SpeechAnalyzer — no audio, cancelling")
                        await analyzer.cancelAndFinishNow()
                    }
                } catch {
                    FileLog.log("SpeechAnalyzer — finalize error: \(error)")
                    await analyzer.cancelAndFinishNow()
                }

                // Wait for result consumer to finish
                guard let (finalText, elapsed) = try? await resultTask.value else {
                    FileLog.log("SpeechAnalyzer — resultTask failed")
                    return
                }
                guard !Task.isCancelled, !finalText.isEmpty else {
                    FileLog.log("SpeechAnalyzer — cancelled or empty after results")
                    return
                }

                FileLog.log("SpeechAnalyzer — final text (\(elapsed)): \(finalText.prefix(80))")
                continuation.yield(.final(FinalTranscription(
                    text: finalText,
                    segments: [],
                    processingTime: elapsed
                )))
            }
        }
    }

    public func cancel() {
        FileLog.log("SpeechAnalyzer — cancel()")
        transcriptionTask?.cancel()
        transcriptionTask = nil
        finishContinuation()
    }

    // MARK: - Private

    private func finishContinuation() {
        guard !continuationFinished else { return }
        continuationFinished = true
        activeContinuation?.finish()
        activeContinuation = nil
    }

    private static func convertToInt16Buffer(samples: [Float]) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: int16AudioFormat, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let int16Ptr = buffer.int16ChannelData![0]
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            int16Ptr[i] = Int16(clamped * 32767.0)
        }
        return buffer
    }
}
