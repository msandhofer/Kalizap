import Foundation
import Accelerate

/// Berechnet ein Frequenz-Spektrum aus Audio-Samples: FFT über 1024 Samples,
/// Hann-Window, Magnitudengruppierung auf 20 logarithmische Bänder
/// im Bereich 80 Hz – 8 kHz, dB-Skala auf [0, 1] geclampt.
///
/// FFT-Setup und Hann-Window werden einmalig im Init erstellt und gecached.
/// Aufrufe sollten aus einem einzigen Thread erfolgen (z. B. Audio-Callback).
public final class AudioSpectrumCalculator: @unchecked Sendable {
    public static let bandCount = 20
    public static let fftSize = 1024

    private static let minFrequency: Float = 80
    private static let maxFrequency: Float = 8_000
    private static let minDb: Float = -60
    private static let maxDb: Float = 0

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]

    public init() {
        self.log2n = vDSP_Length(log2(Float(Self.fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed")
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    public func calculate(from samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty else {
            return [Float](repeating: 0, count: Self.bandCount)
        }

        let windowed = applyWindow(to: samples)
        let magnitudes = computeMagnitudes(windowed)
        return mapToLogBands(magnitudes: magnitudes, sampleRate: sampleRate)
    }

    // MARK: - Private

    private func applyWindow(to samples: [Float]) -> [Float] {
        var buffer = [Float](repeating: 0, count: Self.fftSize)
        if samples.count >= Self.fftSize {
            let start = samples.count - Self.fftSize
            for i in 0..<Self.fftSize {
                buffer[i] = samples[start + i]
            }
        } else {
            for i in 0..<samples.count {
                buffer[i] = samples[i]
            }
        }
        vDSP_vmul(buffer, 1, hannWindow, 1, &buffer, 1, vDSP_Length(Self.fftSize))
        return buffer
    }

    private func computeMagnitudes(_ windowed: [Float]) -> [Float] {
        let halfSize = Self.fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        var amplitudes = [Float](repeating: 0, count: halfSize)
        var len = Int32(halfSize)
        vvsqrtf(&amplitudes, magnitudes, &len)
        return amplitudes
    }

    private func mapToLogBands(magnitudes: [Float], sampleRate: Int) -> [Float] {
        let halfSize = magnitudes.count
        let binWidth = Float(sampleRate) / Float(Self.fftSize)

        let logMin = log2(Self.minFrequency)
        let logMax = log2(Self.maxFrequency)
        let bandWidthLog = (logMax - logMin) / Float(Self.bandCount)

        var bands = [Float](repeating: 0, count: Self.bandCount)

        for band in 0..<Self.bandCount {
            let fLow = pow(2, logMin + Float(band) * bandWidthLog)
            let fHigh = pow(2, logMin + Float(band + 1) * bandWidthLog)
            let kLow = max(0, Int(fLow / binWidth))
            let kHigh = min(halfSize - 1, Int(fHigh / binWidth))

            guard kLow <= kHigh else {
                bands[band] = 0
                continue
            }

            var peak: Float = 0
            for k in kLow...kHigh where magnitudes[k] > peak {
                peak = magnitudes[k]
            }

            let reference = Float(Self.fftSize) / 2
            let normalized = peak / reference
            let db: Float
            if normalized > 0 {
                db = 20 * log10(normalized)
            } else {
                db = Self.minDb
            }
            let clamped = max(Self.minDb, min(Self.maxDb, db))
            bands[band] = (clamped - Self.minDb) / (Self.maxDb - Self.minDb)
        }

        return bands
    }
}
