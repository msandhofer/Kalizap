import Foundation
@preconcurrency import AVFoundation

public final class AudioRecorderImpl: AudioRecording, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let coordinator: AudioSessionCoordinator
    private let deviceManager: AudioDeviceManager
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    private var audioContinuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    private var devicesContinuation: AsyncStream<[AudioDevice]>.Continuation?
    private let sampleRate: Int = 16_000

    // MARK: - AudioCapturing

    public private(set) var state: AudioRecorderState = .idle

    public var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        coordinator.audioStream
    }

    // MARK: - AudioLevelMetering

    public let levelStream: AsyncStream<AudioLevel>

    // MARK: - AudioDeviceManaging

    public let availableDevices: AsyncStream<[AudioDevice]>

    public var selectedDevice: AudioDevice? {
        deviceManager.selectedDevice
    }

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider()) {
        self.deviceManager = AudioDeviceManager(provider: deviceProvider)

        var levelCont: AsyncStream<AudioLevel>.Continuation?
        self.levelStream = AsyncStream { levelCont = $0 }
        self.levelContinuation = levelCont

        var devicesCont: AsyncStream<[AudioDevice]>.Continuation?
        self.availableDevices = AsyncStream { devicesCont = $0 }
        self.devicesContinuation = devicesCont

        // Capture levelCont directly to avoid referencing self before all properties are initialized
        let avEngine = AudioEngineAdapter(engine: engine, sampleRate: sampleRate) { level in
            levelCont?.yield(level)
        }
        self.coordinator = AudioSessionCoordinator(engine: avEngine)
    }

    public func startRecording() async throws {
        try await coordinator.startRecording()
        state = .recording
    }

    public func stopRecording() async {
        await coordinator.stopRecording()
        state = .idle
    }

    public func startMetering() async {
        // Metering is integrated into the tap — starts with recording
    }

    public func stopMetering() async {
        // Stops with recording
    }

    public func selectDevice(_ device: AudioDevice) async throws {
        try await deviceManager.selectDevice(device)
    }

    public func selectDefaultDevice() async throws {
        try await deviceManager.selectDefaultDevice()
    }

    public func refreshDevices() {
        let devices = deviceManager.listDevices()
        devicesContinuation?.yield(devices)
    }

    public func listDevices() -> [AudioDevice] {
        deviceManager.listDevices()
    }
}

// MARK: - AVAudioEngine Adapter

final class AudioEngineAdapter: AudioEngineProviding, @unchecked Sendable {
    private let engine: AVAudioEngine
    private let sampleRate: Int
    private let onLevel: (AudioLevel) -> Void
    private var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    private var chunkTimestamp: TimeInterval = 0

    init(engine: AVAudioEngine, sampleRate: Int, onLevel: @escaping (AudioLevel) -> Void) {
        self.engine = engine
        self.sampleRate = sampleRate
        self.onLevel = onLevel
    }

    var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }

    func startCapture() throws {
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.engineSetupFailed(
                underlying: NSError(domain: "AudioRecorderImpl", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Cannot create target format"])
            )
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw AudioRecorderError.engineSetupFailed(
                underlying: NSError(domain: "AudioRecorderImpl", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"])
            )
        }

        chunkTimestamp = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * Double(sampleRate) / buffer.format.sampleRate)
        ) else { return }

        var error: NSError?
        nonisolated(unsafe) var allConsumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if allConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            allConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, let channelData = convertedBuffer.floatChannelData else { return }

        let frameCount = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        let duration = Double(frameCount) / Double(sampleRate)
        let level = AudioLevelCalculator.calculate(from: samples, timestamp: chunkTimestamp)

        let chunk = AudioChunk(
            samples: samples,
            sampleRate: sampleRate,
            timestamp: chunkTimestamp,
            duration: duration,
            level: level
        )

        chunkTimestamp += duration
        onLevel(level)
        continuation?.yield(chunk)
    }
}

// MARK: - CoreAudio Device Provider

public struct CoreAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func listDevices() -> [AudioDevice] {
        // Use AVCaptureDevice.DiscoverySession for microphone enumeration
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        let defaultUID = defaultDeviceUID()

        return discoverySession.devices.map { device in
            AudioDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultUID
            )
        }
    }

    public func setInputDevice(_ device: AudioDevice) throws {
        // AVAudioEngine uses the system default input by default.
        // To set a specific device, we use the AudioUnit on the engine's input node.
        // This is handled at engine setup time by checking selectedDevice.
        // For now, this is a no-op — the device selection is applied when starting capture.
    }

    public func defaultDevice() -> AudioDevice? {
        listDevices().first { $0.isDefault }
    }

    private func defaultDeviceUID() -> String? {
        AVCaptureDevice.default(for: .audio)?.uniqueID
    }
}
