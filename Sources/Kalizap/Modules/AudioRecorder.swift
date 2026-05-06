import Foundation

public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let level: AudioLevel

    public init(samples: [Float], sampleRate: Int, timestamp: TimeInterval, duration: TimeInterval, level: AudioLevel) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = timestamp
        self.duration = duration
        self.level = level
    }
}

public struct AudioLevel: Sendable, Equatable {
    public let average: Float
    public let peak: Float
    public let timestamp: TimeInterval

    public init(average: Float, peak: Float, timestamp: TimeInterval) {
        self.average = average
        self.peak = peak
        self.timestamp = timestamp
    }
}

public struct AudioDevice: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public enum AudioRecorderState: Sendable, Equatable {
    case idle, recording, paused
}

public enum AudioRecorderError: Error, Sendable {
    case microphoneAccessDenied
    case deviceNotFound(deviceID: String)
    case deviceLost
    case engineSetupFailed(underlying: Error)
}

public protocol AudioCapturing: AnyObject, Sendable {
    var audioStream: AsyncThrowingStream<AudioChunk, Error> { get }
    var state: AudioRecorderState { get }
    func startRecording() async throws
    func stopRecording() async
}

public protocol AudioLevelMetering: AnyObject, Sendable {
    var levelStream: AsyncStream<AudioLevel> { get }
    func startMetering() async
    func stopMetering() async
}

public protocol AudioSpectrumProviding: AnyObject, Sendable {
    /// Register a handler to receive 20 normalized frequency band values [0, 1].
    /// Called from an audio-processing thread. Pass `nil` to remove the handler.
    func setSpectrumHandler(_ handler: (@Sendable ([Float]) -> Void)?)
}

public protocol AudioDeviceManaging: AnyObject, Sendable {
    var availableDevices: AsyncStream<[AudioDevice]> { get }
    var selectedDevice: AudioDevice? { get }
    func selectDevice(_ device: AudioDevice) async throws
    func selectDefaultDevice() async throws
}

public protocol AudioRecording: AudioCapturing, AudioLevelMetering, AudioSpectrumProviding, AudioDeviceManaging {}
