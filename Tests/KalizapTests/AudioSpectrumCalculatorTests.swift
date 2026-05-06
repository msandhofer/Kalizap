import Testing
import Foundation
@testable import Kalizap

@Suite("AudioSpectrumCalculator")
struct AudioSpectrumCalculatorTests {

    @Test("returns 20 bands of zeros for empty samples")
    func emptySamples() {
        let calc = AudioSpectrumCalculator()
        let bands = calc.calculate(from: [], sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test("returns 20 bands of zeros for silence")
    func silence() {
        let calc = AudioSpectrumCalculator()
        let silence = [Float](repeating: 0, count: 2048)
        let bands = calc.calculate(from: silence, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test("all band values are in [0, 1]")
    func clamped() {
        let calc = AudioSpectrumCalculator()
        let samples = (0..<2048).map { i in
            sinf(2 * .pi * 1_000 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("440 Hz sine peaks in a low band")
    func sine440Peak() {
        let calc = AudioSpectrumCalculator()
        let samples = (0..<1024).map { i in
            0.5 * sinf(2 * .pi * 440 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        guard let maxIndex = bands.indices.max(by: { bands[$0] < bands[$1] }) else {
            Issue.record("no max band found")
            return
        }
        #expect(maxIndex < 10)
    }

    @Test("4 kHz sine peaks in a high band")
    func sine4kHzPeak() {
        let calc = AudioSpectrumCalculator()
        let samples = (0..<1024).map { i in
            0.5 * sinf(2 * .pi * 4_000 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        guard let maxIndex = bands.indices.max(by: { bands[$0] < bands[$1] }) else {
            Issue.record("no max band found")
            return
        }
        #expect(maxIndex >= 15)
    }

    @Test("short input is zero-padded and still returns 20 bands")
    func zeroPadShortInput() {
        let calc = AudioSpectrumCalculator()
        let samples: [Float] = [0.1, -0.1, 0.1, -0.1]
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("long input uses last 1024 samples")
    func usesLastSamples() {
        let calc = AudioSpectrumCalculator()
        var samples = [Float](repeating: 0, count: 2000)
        let tone = (0..<2000).map { i in
            0.5 * sinf(2 * .pi * 2_000 * Float(i) / 16_000)
        }
        samples.append(contentsOf: tone)
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.contains { $0 > 0 })
    }

    @Test("fullscale sine near 1 kHz approaches 1.0 in its band")
    func fullscalePeakIsNearOne() {
        let calc = AudioSpectrumCalculator()
        let samples = (0..<1024).map { i in sinf(2 * .pi * 1_000 * Float(i) / 16_000) }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect((bands.max() ?? 0) > 0.7)
    }
}
