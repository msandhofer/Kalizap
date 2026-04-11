import Foundation

public final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private let backend: WhisperBackend
    private var transcriptionTask: Task<Void, Never>?
    private var activeContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var continuationFinished = false

    private static let minSamplesForDecode = 16000 // 1s at 16kHz
    private static let maxSilenceCheckInterval: Duration = .milliseconds(200)
    private static let fallbackDecodeInterval: Duration = .seconds(4)
    private static let tailDecodeInterval: Duration = .seconds(1)
    private static let partialAcceptSamples = 4800 // 0.3s at 16kHz

    public init(backend: WhisperBackend) {
        self.backend = backend
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await backend.loadModel(for: language, onProgress: onProgress)
    }

    public func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult> {
        cancel()

        return AsyncStream { continuation in
            self.activeContinuation = continuation
            self.continuationFinished = false
            let backend = self.backend

            self.transcriptionTask = Task { [weak self] in
                defer { self?.finishContinuation() }

                let buffer = ChunkBuffer()

                // Producer: collect audio chunks into buffer
                let producerTask = Task {
                    for await chunk in audioChunks {
                        guard !Task.isCancelled else { return }
                        await buffer.append(chunk)
                    }
                    await buffer.markEnded()
                }

                // Consumer: VAD-based re-decode at silence boundaries
                var accumulatedText = ""
                var lastDecodedSampleCount = 0
                var lastDecodeTime = ContinuousClock.now
                var lastKnownBoundaryCount = 0

                // Tail-Decode cache (Ansatz C: speculative decode after last VAD boundary)
                var cachedTailText = ""
                var cachedTailSampleCount = 0
                var lastTailDecodeTime = ContinuousClock.now

                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.maxSilenceCheckInterval)
                    guard !Task.isCancelled else { break }
                    if await buffer.isEnded { break }

                    let sampleCount = await buffer.sampleCount
                    guard sampleCount >= Self.minSamplesForDecode else { continue }

                    // Run VAD to detect silence boundaries
                    let samples = await buffer.currentSamples
                    let boundaries = backend.detectSilenceBoundaries(samples: samples)

                    let timeSinceLastDecode = ContinuousClock.now - lastDecodeTime
                    let hasNewBoundary = boundaries.count > lastKnownBoundaryCount
                    let fallbackNeeded = timeSinceLastDecode >= Self.fallbackDecodeInterval
                        && sampleCount > lastDecodedSampleCount + Self.minSamplesForDecode

                    // Check if tail decode is needed (even without VAD/fallback)
                    let tailTimeSinceLastDecode = ContinuousClock.now - lastTailDecodeTime
                    let tailNeeded = lastDecodedSampleCount > 0
                        && tailTimeSinceLastDecode >= Self.tailDecodeInterval
                        && sampleCount > lastDecodedSampleCount + 1600

                    guard hasNewBoundary || fallbackNeeded || tailNeeded else { continue }

                    if hasNewBoundary || fallbackNeeded {
                        // VAD/Fallback decode
                        let samplesToDecodeCount: Int
                        if hasNewBoundary, let lastBoundary = boundaries.last {
                            samplesToDecodeCount = min(Int(lastBoundary * 16000), sampleCount)
                            lastKnownBoundaryCount = boundaries.count
                        } else {
                            samplesToDecodeCount = sampleCount
                        }

                        guard samplesToDecodeCount > lastDecodedSampleCount else { continue }

                        var samplesToTranscribe = Array(samples.prefix(samplesToDecodeCount))
                        AudioProcessingUtils.peakNormalize(&samplesToTranscribe)

                        let decodeStart = ContinuousClock.now
                        do {
                            let result = try await backend.transcribe(
                                samples: samplesToTranscribe,
                                language: config.language.rawValue,
                                prompt: config.initialPrompt
                            )
                            guard !Task.isCancelled else { break }

                            accumulatedText = result.text
                            lastDecodedSampleCount = samplesToDecodeCount
                            lastDecodeTime = ContinuousClock.now

                            let decodeDuration = ContinuousClock.now - decodeStart
                            FileLog.log("VAD re-decode: \(samplesToDecodeCount) samples in \(decodeDuration), boundaries=\(boundaries.count), text=\(result.text.prefix(50))")

                            continuation.yield(.partial(PartialTranscription(
                                text: accumulatedText,
                                confidence: 0
                            )))

                            // Reset tail cache after VAD/fallback decode
                            cachedTailText = ""
                            cachedTailSampleCount = 0
                            lastTailDecodeTime = ContinuousClock.now
                        } catch {
                            FileLog.log("VAD re-decode error: \(error)")
                        }
                    } else if tailNeeded {
                        // Speculative tail decode: decode audio after last VAD boundary
                        let tailSamples = Array(samples[lastDecodedSampleCount..<sampleCount])
                        var normalizedTail = tailSamples
                        AudioProcessingUtils.peakNormalize(&normalizedTail)

                        do {
                            let tailResult = try await backend.transcribe(
                                samples: normalizedTail,
                                language: config.language.rawValue,
                                prompt: accumulatedText
                            )
                            guard !Task.isCancelled else { break }

                            cachedTailText = tailResult.text
                            cachedTailSampleCount = sampleCount
                            lastTailDecodeTime = ContinuousClock.now
                            FileLog.log("Tail decode: \(tailSamples.count) samples, tail=\(tailResult.text.prefix(50))")
                        } catch {
                            FileLog.log("Tail decode error: \(error)")
                        }
                    }
                }

                // Wait for producer to finish
                await producerTask.value
                guard !Task.isCancelled else { return }

                let allSamples = await buffer.currentSamples
                guard !allSamples.isEmpty else {
                    FileLog.log("TranscriptionEngine — empty buffer after stream end")
                    return
                }

                // Final decode: only delta since last silence-based decode
                if lastDecodedSampleCount > 0, lastDecodedSampleCount < allSamples.count {
                    let deltaSamples = Array(allSamples.suffix(from: lastDecodedSampleCount))

                    // Partial-Accept: skip delta decode if remaining audio is very short
                    if deltaSamples.count < Self.partialAcceptSamples {
                        let finalText: String
                        if !cachedTailText.isEmpty {
                            finalText = (accumulatedText + " " + cachedTailText).trimmingCharacters(in: .whitespaces)
                            FileLog.log("TranscriptionEngine — partial-accept with tail cache (\(deltaSamples.count) samples < \(Self.partialAcceptSamples))")
                        } else {
                            finalText = accumulatedText
                            FileLog.log("TranscriptionEngine — partial-accept (\(deltaSamples.count) samples < \(Self.partialAcceptSamples)), using accumulated text")
                        }
                        continuation.yield(.final(FinalTranscription(
                            text: finalText,
                            segments: [],
                            processingTime: .zero,
                            normalizationTime: .zero
                        )))
                    } else if !cachedTailText.isEmpty
                        && (allSamples.count - cachedTailSampleCount) < Self.partialAcceptSamples
                    {
                        // Tail cache is recent enough — use it instead of delta decode
                        let finalText = (accumulatedText + " " + cachedTailText).trimmingCharacters(in: .whitespaces)
                        FileLog.log("TranscriptionEngine — tail-cache accept (\(allSamples.count - cachedTailSampleCount) new samples since cache)")
                        continuation.yield(.final(FinalTranscription(
                            text: finalText,
                            segments: [],
                            processingTime: .zero,
                            normalizationTime: .zero
                        )))
                    } else {
                        // Delta decode with initial_prompt for context
                        var normalizedDelta = deltaSamples
                        let normStart = ContinuousClock.now
                        AudioProcessingUtils.peakNormalize(&normalizedDelta)
                        let normTime = ContinuousClock.now - normStart

                        let start = ContinuousClock.now
                        FileLog.log("TranscriptionEngine — delta decode (\(deltaSamples.count) samples, prompt=\(accumulatedText.suffix(50)))")
                        do {
                            let delta = try await backend.transcribe(
                                samples: normalizedDelta,
                                language: config.language.rawValue,
                                prompt: accumulatedText
                            )
                            let elapsed = ContinuousClock.now - start
                            guard !Task.isCancelled else { return }

                            let finalText = accumulatedText + " " + delta.text
                            FileLog.log("TranscriptionEngine — delta decode done in \(elapsed), final=\(finalText.prefix(80))")

                            continuation.yield(.final(FinalTranscription(
                                text: finalText.trimmingCharacters(in: .whitespaces),
                                segments: delta.segments,
                                processingTime: elapsed,
                                normalizationTime: normTime
                            )))
                        } catch {
                            FileLog.log("TranscriptionEngine — delta decode ERROR: \(error), using accumulated text")
                            continuation.yield(.final(FinalTranscription(
                                text: accumulatedText,
                                segments: [],
                                processingTime: .zero
                            )))
                        }
                    }
                } else {
                    // No re-decode happened — full decode (short dictation or no VAD)
                    var normalizedSamples = allSamples
                    let normStart = ContinuousClock.now
                    AudioProcessingUtils.peakNormalize(&normalizedSamples)
                    let normTime = ContinuousClock.now - normStart

                    let start = ContinuousClock.now
                    FileLog.log("TranscriptionEngine — full decode (\(allSamples.count) samples)")
                    do {
                        let result = try await backend.transcribe(
                            samples: normalizedSamples,
                            language: config.language.rawValue,
                            prompt: config.initialPrompt
                        )
                        let elapsed = ContinuousClock.now - start
                        guard !Task.isCancelled else { return }

                        FileLog.log("TranscriptionEngine — full decode done in \(elapsed)")
                        continuation.yield(.final(FinalTranscription(
                            text: result.text,
                            segments: result.segments,
                            processingTime: elapsed,
                            normalizationTime: normTime
                        )))
                    } catch {
                        FileLog.log("TranscriptionEngine — full decode ERROR: \(error)")
                    }
                }
            }
        }
    }

    public func cancel() {
        FileLog.log("TranscriptionEngine — cancel() called")
        transcriptionTask?.cancel()
        transcriptionTask = nil
        finishContinuation()
    }

    private func finishContinuation() {
        guard !continuationFinished else { return }
        continuationFinished = true
        activeContinuation?.finish()
        activeContinuation = nil
    }
}

// MARK: - ChunkBuffer

private actor ChunkBuffer {
    private var samples: [Float] = []
    private var ended = false

    var isEnded: Bool { ended }
    var currentSamples: [Float] { samples }
    var sampleCount: Int { samples.count }

    func append(_ chunk: AudioChunk) {
        samples.append(contentsOf: chunk.samples)
    }

    func markEnded() {
        ended = true
    }
}
