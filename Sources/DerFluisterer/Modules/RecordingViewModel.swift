import Foundation
import Observation

@Observable
@MainActor
public final class RecordingViewModel {
    public private(set) var isRecording = false
    public private(set) var isPulsing = false
    public private(set) var waveformLevels: [Float] = []
    private let maxBars: Int

    public var menuBarIcon: String {
        isRecording ? "waveform" : "mic.fill"
    }

    public init(maxWaveformBars: Int = 20) {
        self.maxBars = maxWaveformBars
    }

    public func startRecording() {
        isRecording = true
        isPulsing = true
        waveformLevels = []
    }

    public func stopRecording() {
        isRecording = false
        isPulsing = false
        waveformLevels = []
    }

    public func updateLevel(_ level: AudioLevel) {
        guard isRecording else { return }
        waveformLevels.append(level.peak)
        if waveformLevels.count > maxBars {
            waveformLevels.removeFirst(waveformLevels.count - maxBars)
        }
    }
}
