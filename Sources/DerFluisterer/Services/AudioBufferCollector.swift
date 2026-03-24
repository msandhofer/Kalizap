import Foundation

public struct CollectedAudioBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let totalDuration: TimeInterval

    public init(samples: [Float], sampleRate: Int, totalDuration: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.totalDuration = totalDuration
    }
}

public enum AudioBufferCollector {
    public static func collect(from stream: AsyncStream<AudioChunk>) async -> CollectedAudioBuffer {
        var allSamples: [Float] = []
        var sampleRate = 16000
        var totalDuration: TimeInterval = 0

        for await chunk in stream {
            allSamples.append(contentsOf: chunk.samples)
            sampleRate = chunk.sampleRate
            totalDuration += chunk.duration
        }

        return CollectedAudioBuffer(
            samples: allSamples,
            sampleRate: sampleRate,
            totalDuration: totalDuration
        )
    }
}
