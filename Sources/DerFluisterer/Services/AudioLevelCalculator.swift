import Foundation

public enum AudioLevelCalculator {
    public static func calculate(from samples: [Float], timestamp: TimeInterval) -> AudioLevel {
        guard !samples.isEmpty else {
            return AudioLevel(average: 0.0, peak: 0.0, timestamp: timestamp)
        }

        var sumOfSquares: Float = 0.0
        var peak: Float = 0.0

        for sample in samples {
            let absolute = abs(sample)
            sumOfSquares += sample * sample
            if absolute > peak {
                peak = absolute
            }
        }

        let rms = sqrt(sumOfSquares / Float(samples.count))
        return AudioLevel(average: rms, peak: peak, timestamp: timestamp)
    }
}
