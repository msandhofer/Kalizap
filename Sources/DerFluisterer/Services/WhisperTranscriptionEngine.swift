import Foundation

public final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private let backend: WhisperBackend
    private var cancelled = false
    private var transcriptionTask: Task<Void, Never>?
    private var activeContinuation: AsyncStream<TranscriptionResult>.Continuation?

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
        cancelled = false

        return AsyncStream { continuation in
            self.activeContinuation = continuation
            let backend = self.backend

            self.transcriptionTask = Task { [weak self] in
                var allSamples: [Float] = []
                FileLog.log("TranscriptionEngine — collecting audio chunks")
                for await chunk in audioChunks {
                    guard self?.cancelled != true else {
                        FileLog.log("TranscriptionEngine — cancelled during chunk collection")
                        continuation.finish()
                        self?.activeContinuation = nil
                        return
                    }
                    allSamples.append(contentsOf: chunk.samples)
                }

                FileLog.log("TranscriptionEngine — collected \(allSamples.count) samples, cancelled=\(self?.cancelled ?? true)")
                guard self?.cancelled != true, !allSamples.isEmpty else {
                    FileLog.log("TranscriptionEngine — bailing out (cancelled or empty)")
                    continuation.finish()
                    self?.activeContinuation = nil
                    return
                }

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

                    guard self?.cancelled != true else {
                        FileLog.log("TranscriptionEngine — cancelled after transcription")
                        continuation.finish()
                        self?.activeContinuation = nil
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

                continuation.finish()
                self?.activeContinuation = nil
            }
        }
    }

    public func cancel() {
        FileLog.log("TranscriptionEngine — cancel() called")
        cancelled = true
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeContinuation?.finish()
        activeContinuation = nil
    }
}
