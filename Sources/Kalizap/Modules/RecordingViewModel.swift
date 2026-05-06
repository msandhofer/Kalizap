import Foundation
import Observation

@Observable
@MainActor
public final class RecordingViewModel {
    public private(set) var isRecording = false
    public private(set) var isPulsing = false

    public var menuBarIcon: String {
        isRecording ? "waveform" : "mic.fill"
    }

    public init() {}

    public func startRecording() {
        isRecording = true
        isPulsing = true
    }

    public func stopRecording() {
        isRecording = false
        isPulsing = false
    }
}
