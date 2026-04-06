import Foundation
import os.log
import CWhisper

private let logger = Logger(subsystem: "com.derfluesterer", category: "WhisperCpp")

public final class WhisperCppBackend: WhisperBackend, @unchecked Sendable {
    private var ctx: OpaquePointer? // whisper_context*
    private let modelName: String
    private var languagePointer: UnsafeMutablePointer<CChar>?
    private var promptPointer: UnsafeMutablePointer<CChar>?

    public init(model: String = "base") {
        self.modelName = model
    }

    deinit {
        if let ctx { whisper_free(ctx) }
        freeStringPointers()
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws {
        guard let model = WhisperModel(rawValue: modelName) else {
            throw TranscriptionError.modelLoadFailed(reason: "Unknown model: \(modelName)")
        }

        FileLog.log("WhisperCppBackend.loadModel START — model=\(modelName)")
        do {
            let modelURL = try await withoutActuallyEscaping(onProgress) { escapingProgress in
                try await GGMLModelManager.shared.downloadModel(model, onProgress: escapingProgress)
            }
            FileLog.log("  GGML model ready at \(modelURL.path)")

            ctx = whisper_init_from_file(modelURL.path)
            guard ctx != nil else {
                throw TranscriptionError.modelLoadFailed(reason: "whisper_init_from_file returned nil")
            }
            FileLog.log("  Whisper context created")
            onProgress(1.0)
        } catch {
            FileLog.log("  WhisperCpp loadModel FAILED: \(error)")
            throw TranscriptionError.modelLoadFailed(reason: error.localizedDescription)
        }
    }

    public func transcribe(
        samples: [Float],
        language: String,
        prompt: String
    ) async throws -> WhisperTranscriptionResult {
        guard let ctx else {
            throw TranscriptionError.modelNotLoaded
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false

        freeStringPointers()
        languagePointer = strdup(language)
        params.language = UnsafePointer(languagePointer)

        if !prompt.isEmpty {
            promptPointer = strdup(prompt)
            params.initial_prompt = UnsafePointer(promptPointer)
        }

        // whisper_full is synchronous/blocking — run everything on background thread
        // Use nonisolated(unsafe) to pass OpaquePointer across isolation boundary
        nonisolated(unsafe) let unsafeCtx = ctx
        let capturedParams = params

        let result: WhisperTranscriptionResult = try await Task.detached(priority: .userInitiated) {
            let ret = samples.withUnsafeBufferPointer { buf in
                whisper_full(unsafeCtx, capturedParams, buf.baseAddress, Int32(buf.count))
            }

            guard ret == 0 else {
                throw TranscriptionError.batchFailed(reason: "whisper_full returned \(ret)")
            }

            let nSegments = whisper_full_n_segments(unsafeCtx)
            var segments: [TranscriptionSegment] = []
            var fullText = ""

            for i in 0..<nSegments {
                guard let cText = whisper_full_get_segment_text(unsafeCtx, i) else { continue }
                let text = String(cString: cText)
                let t0 = whisper_full_get_segment_t0(unsafeCtx, i) * 10 // centiseconds → milliseconds
                let t1 = whisper_full_get_segment_t1(unsafeCtx, i) * 10

                fullText += text
                segments.append(TranscriptionSegment(
                    text: text,
                    range: Duration.milliseconds(t0)..<Duration.milliseconds(t1),
                    confidence: 0.0
                ))
            }

            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            return WhisperTranscriptionResult(text: trimmed, segments: segments)
        }.value

        return result
    }

    private func freeStringPointers() {
        if let ptr = languagePointer { free(ptr); languagePointer = nil }
        if let ptr = promptPointer { free(ptr); promptPointer = nil }
    }
}
