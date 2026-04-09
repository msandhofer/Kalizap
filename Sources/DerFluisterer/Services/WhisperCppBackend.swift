import Foundation
import os.log
import CWhisper

private let logger = Logger(subsystem: "com.derfluesterer", category: "WhisperCpp")

public final class WhisperCppBackend: WhisperBackend, @unchecked Sendable {
    private var ctx: OpaquePointer? // whisper_context*
    private var vadCtx: OpaquePointer? // whisper_vad_context*
    private let modelName: String
    private let useCoreML: Bool
    private var languagePointer: UnsafeMutablePointer<CChar>?
    private var promptPointer: UnsafeMutablePointer<CChar>?

    public init(model: String = "base", useCoreML: Bool = false) {
        self.modelName = model
        self.useCoreML = useCoreML
    }

    deinit {
        if let ctx { whisper_free(ctx) }
        if let vadCtx { whisper_vad_free(vadCtx) }
        freeStringPointers()
    }

    public func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let model = WhisperModel(rawValue: modelName) else {
            throw TranscriptionError.modelLoadFailed(reason: "Unknown model: \(modelName)")
        }

        FileLog.log("WhisperCppBackend.loadModel START — model=\(modelName), coreml=\(useCoreML)")
        do {
            let modelURL = try await GGMLModelManager.shared.downloadModel(model, onProgress: onProgress)
            let vadURL = try await GGMLModelManager.shared.downloadVADModel { _ in }
            FileLog.log("  GGML model ready at \(modelURL.path)")
            FileLog.log("  VAD model ready at \(vadURL.path)")

            // CoreML encoder: download if enabled, disable if not
            if useCoreML {
                let coremlURL = try await GGMLModelManager.shared.downloadCoreMLEncoder(for: model, onProgress: onProgress)
                try GGMLModelManager.shared.setCoreMLEncoderEnabled(true, for: model)
                FileLog.log("  CoreML encoder ready at \(coremlURL.path)")
            } else {
                try? GGMLModelManager.shared.setCoreMLEncoderEnabled(false, for: model)
                FileLog.log("  CoreML disabled")
            }

            var ctxParams = whisper_context_default_params()
            ctxParams.use_gpu = true
            ctxParams.flash_attn = true
            ctx = whisper_init_from_file_with_params(modelURL.path, ctxParams)
            guard ctx != nil else {
                throw TranscriptionError.modelLoadFailed(reason: "whisper_init_from_file_with_params returned nil")
            }

            var vadCtxParams = whisper_vad_default_context_params()
            vadCtx = whisper_vad_init_from_file_with_params(vadURL.path, vadCtxParams)
            FileLog.log("  Whisper + VAD contexts created (VAD=\(vadCtx != nil))")
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
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.single_segment = true
        params.suppress_blank = true
        params.temperature_inc = 0

        if useCoreML {
            // CoreML encoder is compiled for fixed 1500-frame input — must always use full size
            params.audio_ctx = 1500
        } else {
            // Optimize audio_ctx for Metal/CPU — smaller context = faster for short audio
            let melFrames = Int(ceil(Double(samples.count) / 16000.0 * 100.0))
            let aligned = ((melFrames + 63) / 64) * 64
            params.audio_ctx = Int32(max(768, min(aligned, 1500)))
        }

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
            // Fresh state per transcription — prevents encoder state leaking between calls
            guard let state = whisper_init_state(unsafeCtx) else {
                throw TranscriptionError.batchFailed(reason: "whisper_init_state returned nil")
            }
            defer { whisper_free_state(state) }

            let ret = samples.withUnsafeBufferPointer { buf in
                whisper_full_with_state(unsafeCtx, state, capturedParams, buf.baseAddress, Int32(buf.count))
            }

            guard ret == 0 else {
                throw TranscriptionError.batchFailed(reason: "whisper_full_with_state returned \(ret)")
            }

            let nSegments = whisper_full_n_segments_from_state(state)
            var segments: [TranscriptionSegment] = []
            var fullText = ""

            for i in 0..<nSegments {
                guard let cText = whisper_full_get_segment_text_from_state(state, i) else { continue }
                let text = String(cString: cText)
                let t0 = whisper_full_get_segment_t0_from_state(state, i) * 10 // centiseconds → milliseconds
                let t1 = whisper_full_get_segment_t1_from_state(state, i) * 10

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

    public func detectSilenceBoundaries(samples: [Float]) -> [Float] {
        guard let vadCtx else { return [] }

        var vadParams = whisper_vad_default_params()
        vadParams.min_silence_duration_ms = 300
        vadParams.speech_pad_ms = 50

        guard let segments = samples.withUnsafeBufferPointer({ buf in
            whisper_vad_segments_from_samples(vadCtx, vadParams, buf.baseAddress, Int32(buf.count))
        }) else { return [] }
        defer { whisper_vad_free_segments(segments) }

        let n = whisper_vad_segments_n_segments(segments)
        guard n > 0 else { return [] }

        // Return end-times of speech segments (= start of silence)
        var boundaries: [Float] = []
        for i in 0..<n {
            let t1 = whisper_vad_segments_get_segment_t1(segments, i)
            boundaries.append(t1)
        }
        return boundaries
    }

    private func freeStringPointers() {
        if let ptr = languagePointer { free(ptr); languagePointer = nil }
        if let ptr = promptPointer { free(ptr); promptPointer = nil }
    }
}
