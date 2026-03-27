import Foundation
import Accelerate
import CDeepFilter

public final class DeepFilterProcessor: NoiseSuppressionProcessing, @unchecked Sendable {
    public let inputSampleRate: Int = 48_000
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

    /// Downsample from 48kHz to 16kHz using simple 3:1 decimation with averaging.
    public static func downsample48to16(_ samples: [Float]) -> [Float] {
        let outputCount = samples.count / 3
        guard outputCount > 0 else { return [] }
        var result = [Float](repeating: 0, count: outputCount)
        // Simple averaging filter (anti-alias by averaging 3 samples)
        for i in 0..<outputCount {
            let base = i * 3
            result[i] = (samples[base] + samples[base + 1] + samples[base + 2]) / 3.0
        }
        return result
    }

    /// Peak-normalize samples to target level using vDSP.
    /// Returns the applied gain factor.
    @discardableResult
    public static func peakNormalize(_ samples: inout [Float], targetPeak: Float = 0.9) -> Float {
        guard !samples.isEmpty else { return 1.0 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0.001 else { return 1.0 }
        let gain = targetPeak / peak
        vDSP_vsmul(samples, 1, [gain], &samples, 1, vDSP_Length(samples.count))
        return gain
    }
}

public enum DeepFilterError: Error, Sendable {
    case modelLoadFailed(path: String)
    case modelNotFound
}
