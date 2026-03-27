import Foundation

public protocol NoiseSuppressionProcessing: Sendable {
    /// The sample rate expected by this processor (e.g. 48000 for DeepFilterNet3).
    var inputSampleRate: Int { get }

    /// Process a buffer of Float samples at `inputSampleRate`.
    /// Returns processed samples at the same rate.
    /// Thread-safety: must be called from a single serial context (audio callback).
    func processFrame(_ input: inout [Float], output: inout [Float])

    /// The number of samples per processing frame.
    var frameSize: Int { get }
}

/// A pass-through that does nothing (used when noise suppression is disabled).
public final class NoOpNoiseSuppressor: NoiseSuppressionProcessing, @unchecked Sendable {
    public let inputSampleRate: Int
    public let frameSize: Int = 0

    public init(sampleRate: Int = 16_000) {
        self.inputSampleRate = sampleRate
    }

    public func processFrame(_ input: inout [Float], output: inout [Float]) {
        output = input
    }
}
