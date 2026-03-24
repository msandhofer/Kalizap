import Foundation

struct AudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let timestamp: TimeInterval
    let duration: TimeInterval
    let level: AudioLevel
}

struct AudioLevel: Sendable {
    let average: Float
    let peak: Float
    let timestamp: TimeInterval
}

struct AudioDevice: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
}

enum AudioRecorderState: Sendable {
    case idle, recording, paused
}

enum AudioRecorderError: Error, Sendable {
    case microphoneAccessDenied
    case deviceNotFound(deviceID: String)
    case deviceLost
    case engineSetupFailed(underlying: Error)
}

protocol AudioCapturing: AnyObject, Sendable {
    var audioStream: AsyncThrowingStream<AudioChunk, Error> { get }
    var state: AudioRecorderState { get }
    func startRecording() async throws
    func stopRecording() async
}

protocol AudioLevelMetering: AnyObject, Sendable {
    var levelStream: AsyncStream<AudioLevel> { get }
    func startMetering() async
    func stopMetering() async
}

protocol AudioDeviceManaging: AnyObject, Sendable {
    var availableDevices: AsyncStream<[AudioDevice]> { get }
    var selectedDevice: AudioDevice? { get }
    func selectDevice(_ device: AudioDevice) async throws
    func selectDefaultDevice() async throws
}

protocol AudioRecording: AudioCapturing, AudioLevelMetering, AudioDeviceManaging {}
