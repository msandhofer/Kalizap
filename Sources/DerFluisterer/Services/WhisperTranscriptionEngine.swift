import Foundation

public final class WhisperTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private let backend: WhisperBackend
    private var cancelled = false

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
            let backend = self.backend

            Task { [weak self] in
                var allSamples: [Float] = []
                for await chunk in audioChunks {
                    guard self?.cancelled != true else {
                        continuation.finish()
                        return
                    }
                    allSamples.append(contentsOf: chunk.samples)
                }

                guard self?.cancelled != true, !allSamples.isEmpty else {
                    continuation.finish()
                    return
                }

                do {
                    let start = ContinuousClock.now
                    let result = try await backend.transcribe(
                        samples: allSamples,
                        language: config.language.rawValue,
                        prompt: config.initialPrompt
                    )
                    let elapsed = ContinuousClock.now - start

                    guard self?.cancelled != true else {
                        continuation.finish()
                        return
                    }

                    let final_ = FinalTranscription(
                        text: result.text,
                        segments: result.segments,
                        processingTime: elapsed
                    )
                    continuation.yield(.final(final_))
                } catch {
                    // Stream ends without result on error
                }

                continuation.finish()
            }
        }
    }

    public func cancel() {
        cancelled = true
    }
}
