import Foundation
import CDeepFilter

public final class DeepFilterProcessor: @unchecked Sendable {
    public let inputSampleRate: Int = AudioProcessingUtils.deepFilterSampleRate
    public private(set) var frameSize: Int

    private let state: OpaquePointer
    private var inputBuffer: [Float] = []

    /// Create a DeepFilterNet3 processor.
    /// - Parameter modelPath: Path to DeepFilterNet3_onnx.tar.gz
    /// - Parameter attenuationLimit: Max attenuation in dB (100 = no limit)
    public init(modelPath: String, attenuationLimit: Float = 100.0) throws {
        guard let s = df_create(modelPath, attenuationLimit, nil) else {
            throw DeepFilterError.modelLoadFailed(path: modelPath)
        }
        self.state = s
        self.frameSize = Int(df_get_frame_length(s))
    }

    deinit {
        df_free(state)
    }

    public func processFrame(_ input: inout [Float], output: inout [Float]) {
        guard input.count == frameSize else {
            output = input
            return
        }
        output = [Float](repeating: 0, count: frameSize)
        _ = df_process_frame(state, &input, &output)
    }

    /// Process a variable-length chunk by buffering into fixed-size frames.
    /// Returns processed samples (may be fewer than input if partial frame remains).
    public func processChunk(_ samples: [Float]) -> [Float] {
        inputBuffer.append(contentsOf: samples)

        var result: [Float] = []
        result.reserveCapacity(inputBuffer.count)

        while inputBuffer.count >= frameSize {
            var inFrame = Array(inputBuffer.prefix(frameSize))
            var outFrame = [Float](repeating: 0, count: frameSize)
            _ = df_process_frame(state, &inFrame, &outFrame)
            result.append(contentsOf: outFrame)
            inputBuffer.removeFirst(frameSize)
        }

        return result
    }

    /// Reset the internal input buffer (call when starting a new recording).
    public func resetBuffer() {
        inputBuffer = []
    }

}

public enum DeepFilterError: Error, Sendable {
    case modelLoadFailed(path: String)
    case modelNotFound
}
