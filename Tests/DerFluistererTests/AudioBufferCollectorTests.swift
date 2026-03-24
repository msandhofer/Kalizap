import Testing
import Foundation
@testable import DerFluisterer

@Suite("AudioBufferCollector")
struct AudioBufferCollectorTests {

    @Test("collects single chunk into buffer")
    func singleChunk() async {
        let chunks = [makeTestChunk(samples: [0.1, 0.2, 0.3])]
        let buffer = await AudioBufferCollector.collect(from: makeTestAudioStream(chunks))
        #expect(buffer.samples == [0.1, 0.2, 0.3])
        #expect(buffer.sampleRate == 16000)
    }

    @Test("concatenates multiple chunks in order")
    func multipleChunks() async {
        let chunks = [
            makeTestChunk(samples: [0.1, 0.2]),
            makeTestChunk(samples: [0.3, 0.4]),
            makeTestChunk(samples: [0.5]),
        ]
        let buffer = await AudioBufferCollector.collect(from: makeTestAudioStream(chunks))
        #expect(buffer.samples == [0.1, 0.2, 0.3, 0.4, 0.5])
    }

    @Test("empty stream produces empty buffer")
    func emptyStream() async {
        let buffer = await AudioBufferCollector.collect(from: makeTestAudioStream([]))
        #expect(buffer.samples.isEmpty)
        #expect(buffer.totalDuration == 0)
    }

    @Test("calculates total duration")
    func totalDuration() async {
        let samples = [Float](repeating: 0.1, count: 48000)
        let chunks = [makeTestChunk(samples: samples)]
        let buffer = await AudioBufferCollector.collect(from: makeTestAudioStream(chunks))
        #expect(abs(buffer.totalDuration - 3.0) < 0.01)
    }
}
