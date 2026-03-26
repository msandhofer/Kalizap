import Foundation
import os.log
import WhisperKit

private let logger = Logger(subsystem: "com.derfluesterer", category: "WhisperKit")

public final class WhisperKitBackend: WhisperBackend, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let modelName: String

    public init(model: String = "openai_whisper-large-v3_turbo") {
        self.modelName = model
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        FileLog.log("WhisperKitBackend.loadModel START — model=\(modelName)")
        FileLog.log("  Task.isCancelled=\(Task.isCancelled)")
        do {
            let config = WhisperKitConfig(
                model: modelName,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: true,
                logLevel: .debug,
                prewarm: true
            )
            FileLog.log("  WhisperKitConfig created, calling WhisperKit(config)...")
            FileLog.log("  Task.isCancelled before WhisperKit init=\(Task.isCancelled)")
            whisperKit = try await WhisperKit(config)
            FileLog.log("  WhisperKit init SUCCESS")
            onProgress(1.0)
        } catch {
            let reason = String(describing: error)
            FileLog.log("  WhisperKit init FAILED: \(reason)")
            FileLog.log("  Task.isCancelled after error=\(Task.isCancelled)")
            throw TranscriptionError.modelLoadFailed(reason: reason)
        }
    }

    public func transcribe(
        samples: [Float],
        language: String,
        prompt: String
    ) async throws -> WhisperTranscriptionResult {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        do {
            var options = DecodingOptions(
                verbose: true,
                language: language
            )

            if !prompt.isEmpty, let tokenizer = whisperKit.tokenizer {
                options.promptTokens = tokenizer.encode(text: prompt)
            }

            let results = try await whisperKit.transcribe(
                audioArrays: [samples],
                decodeOptions: options
            )

            guard let firstGroup = results.first, let group = firstGroup, let first = group.first else {
                throw TranscriptionError.batchFailed(reason: "No transcription result returned")
            }

            let text = first.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            let segments = first.segments.map { segment in
                TranscriptionSegment(
                    text: segment.text,
                    range: Duration.seconds(Double(segment.start))..<Duration.seconds(Double(segment.end)),
                    confidence: segment.avgLogprob
                )
            }

            return WhisperTranscriptionResult(text: text, segments: segments)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.batchFailed(reason: error.localizedDescription)
        }
    }
}
