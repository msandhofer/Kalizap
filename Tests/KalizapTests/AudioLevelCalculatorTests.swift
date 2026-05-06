import Testing
import Foundation
@testable import Kalizap

@Suite("AudioLevelCalculator")
struct AudioLevelCalculatorTests {

    @Test("calculates RMS average from samples")
    func rmsAverage() {
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        let level = AudioLevelCalculator.calculate(from: samples, timestamp: 0)
        // RMS of [0.5, -0.5, 0.5, -0.5] = sqrt(mean(0.25, 0.25, 0.25, 0.25)) = sqrt(0.25) = 0.5
        #expect(abs(level.average - 0.5) < 0.001)
    }

    @Test("calculates peak from samples")
    func peak() {
        let samples: [Float] = [0.1, -0.8, 0.3, -0.2]
        let level = AudioLevelCalculator.calculate(from: samples, timestamp: 0)
        #expect(abs(level.peak - 0.8) < 0.001)
    }

    @Test("returns zero level for empty samples")
    func emptySamples() {
        let level = AudioLevelCalculator.calculate(from: [], timestamp: 0)
        #expect(level.average == 0.0)
        #expect(level.peak == 0.0)
    }

    @Test("passes through timestamp")
    func timestamp() {
        let level = AudioLevelCalculator.calculate(from: [0.5], timestamp: 42.0)
        #expect(level.timestamp == 42.0)
    }

    @Test("silence produces zero level")
    func silence() {
        let samples = [Float](repeating: 0.0, count: 1000)
        let level = AudioLevelCalculator.calculate(from: samples, timestamp: 0)
        #expect(level.average == 0.0)
        #expect(level.peak == 0.0)
    }
}
