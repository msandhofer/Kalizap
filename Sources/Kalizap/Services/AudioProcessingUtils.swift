import Foundation
import Accelerate

/// Shared audio processing utilities used across the pipeline.
public enum AudioProcessingUtils {

    /// Standard sample rate for transcription (16 kHz).
    public static let transcriptionSampleRate = 16_000

    /// Sample rate required by DeepFilterNet3 (48 kHz).
    public static let deepFilterSampleRate = 48_000

    /// Downsample from 48kHz to 16kHz using simple 3:1 decimation with averaging.
    public static func downsample48to16(_ samples: [Float]) -> [Float] {
        let outputCount = samples.count / 3
        guard outputCount > 0 else { return [] }
        var result = [Float](repeating: 0, count: outputCount)
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
