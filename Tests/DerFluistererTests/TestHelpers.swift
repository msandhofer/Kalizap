import Foundation
@testable import DerFluisterer

// MARK: - Shared Mocks

final class MockSoundBackend: SoundBackend, @unchecked Sendable {
    var playedSounds: [SoundEffect] = []

    func play(_ sound: SoundEffect) {
        playedSounds.append(sound)
    }
}

// MARK: - Factory Helpers

func makeTestChunk(
    samples: [Float] = [0.1, 0.2, 0.3],
    sampleRate: Int = 16000,
    timestamp: TimeInterval = 0
) -> AudioChunk {
    let duration = Double(samples.count) / Double(sampleRate)
    let level = AudioLevelCalculator.calculate(from: samples, timestamp: timestamp)
    return AudioChunk(
        samples: samples,
        sampleRate: sampleRate,
        timestamp: timestamp,
        duration: duration,
        level: level
    )
}

func makeTestAudioStream(_ chunks: [AudioChunk]) -> AsyncStream<AudioChunk> {
    AsyncStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}
