import Foundation

public final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private let backend: WhisperBackend
    private var transcriptionTask: Task<Void, Never>?
    private var activeContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var continuationFinished = false

    public init(backend: WhisperBackend) {
        self.backend = backend
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
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

                var allSamples: [Float] = []
                FileLog.log("TranscriptionEngine — collecting audio chunks")
                for await chunk in audioChunks {
                    guard !Task.isCancelled else {
                        FileLog.log("TranscriptionEngine — cancelled during chunk collection")
                        return
                    }
                    allSamples.append(contentsOf: chunk.samples)
                }

                guard !Task.isCancelled, !allSamples.isEmpty else {
                    FileLog.log("TranscriptionEngine — bailing out (cancelled=\(Task.isCancelled), empty=\(allSamples.isEmpty))")
                    return
                }

                AudioProcessingUtils.peakNormalize(&allSamples)

                do {
                    let start = ContinuousClock.now
                    FileLog.log("TranscriptionEngine — calling backend.transcribe (\(allSamples.count) samples)")
                    let result = try await backend.transcribe(
                        samples: allSamples,
                        language: config.language.rawValue,
                        prompt: config.initialPrompt
                    )
                    let elapsed = ContinuousClock.now - start
                    FileLog.log("TranscriptionEngine — backend returned in \(elapsed), text=\(result.text.prefix(50))")

                    guard !Task.isCancelled else {
                        FileLog.log("TranscriptionEngine — cancelled after transcription")
                        return
                    }

                    let final_ = FinalTranscription(
                        text: result.text,
                        segments: result.segments,
                        processingTime: elapsed
                    )
                    continuation.yield(.final(final_))
                } catch {
                    FileLog.log("TranscriptionEngine — ERROR: \(error)")
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
