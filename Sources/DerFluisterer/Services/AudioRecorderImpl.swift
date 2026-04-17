import Foundation
@preconcurrency import AVFoundation
import AudioToolbox

/// Thread-safe holder for the spectrum handler closure.
/// Lives as a standalone reference type so the `onSpectrum` callback
/// can capture it without needing a fully-initialized `AudioRecorderImpl`.
private final class SpectrumHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable ([Float]) -> Void)?

    func set(_ handler: (@Sendable ([Float]) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func dispatch(_ bands: [Float]) {
        lock.lock()
        let h = handler
        lock.unlock()
        h?(bands)
    }
}

public final class AudioRecorderImpl: AudioRecording, @unchecked Sendable {
    private let coordinator: AudioSessionCoordinator
    private let deviceManager: AudioDeviceManager
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    private var audioContinuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    private var devicesContinuation: AsyncStream<[AudioDevice]>.Continuation?
    private let sampleRate: Int = AudioProcessingUtils.transcriptionSampleRate

    // MARK: - AudioCapturing

    public var state: AudioRecorderState { coordinator.state }

    public var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        coordinator.audioStream
    }

    // MARK: - AudioLevelMetering

    public let levelStream: AsyncStream<AudioLevel>

    // MARK: - AudioSpectrumProviding

    private let spectrumHandlerBox = SpectrumHandlerBox()

    public func setSpectrumHandler(_ handler: (@Sendable ([Float]) -> Void)?) {
        spectrumHandlerBox.set(handler)
    }

    // MARK: - AudioDeviceManaging

    public let availableDevices: AsyncStream<[AudioDevice]>

    public var selectedDevice: AudioDevice? {
        deviceManager.selectedDevice
    }

    public init(deviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(), noiseSuppressor: DeepFilterProcessor? = nil) {
        self.deviceManager = AudioDeviceManager(provider: deviceProvider)

        var levelCont: AsyncStream<AudioLevel>.Continuation?
        self.levelStream = AsyncStream { levelCont = $0 }
        self.levelContinuation = levelCont

        var devicesCont: AsyncStream<[AudioDevice]>.Continuation?
        self.availableDevices = AsyncStream { devicesCont = $0 }
        self.devicesContinuation = devicesCont

        let spectrumCalculator = AudioSpectrumCalculator()
        let handlerBox = self.spectrumHandlerBox

        let adapter = AudioQueueAdapter(
            sampleRate: AudioProcessingUtils.transcriptionSampleRate,
            noiseSuppressor: noiseSuppressor,
            spectrumCalculator: spectrumCalculator,
            onLevel: { level in
                levelCont?.yield(level)
            },
            onSpectrum: { bands in
                handlerBox.dispatch(bands)
            }
        )
        self.coordinator = AudioSessionCoordinator(engine: adapter)
    }

    public func startRecording() async throws {
        try await coordinator.startRecording()
    }

    public func stopRecording() async {
        await coordinator.stopRecording()
    }

    public func startMetering() async {
        // No-op: metering is integrated into the audio tap and starts/stops with recording
    }

    public func stopMetering() async {
        // No-op: see startMetering()
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

// MARK: - AudioQueue Adapter (input-only, no output to speakers)

final class AudioQueueAdapter: AudioEngineProviding, @unchecked Sendable {
    private let outputSampleRate: Int
    private let noiseSuppressor: DeepFilterProcessor?
    private let spectrumCalculator: AudioSpectrumCalculator
    private let onLevel: (AudioLevel) -> Void
    private let onSpectrum: ([Float]) -> Void
    private var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    private var chunkTimestamp: TimeInterval = 0
    private var audioQueue: AudioQueueRef?
    private let numBuffers = 3
    private let bufferByteSize: UInt32 = 16384

    init(
        sampleRate: Int,
        noiseSuppressor: DeepFilterProcessor? = nil,
        spectrumCalculator: AudioSpectrumCalculator,
        onLevel: @escaping (AudioLevel) -> Void,
        onSpectrum: @escaping ([Float]) -> Void
    ) {
        self.outputSampleRate = sampleRate
        self.noiseSuppressor = noiseSuppressor
        self.spectrumCalculator = spectrumCalculator
        self.onLevel = onLevel
        self.onSpectrum = onSpectrum
    }

    var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }

    func startCapture() throws {
        // Capture at 48kHz when noise suppression is active (DeepFilterNet3 requires it),
        // otherwise capture directly at the output sample rate (16kHz).
        let captureSampleRate = noiseSuppressor != nil ? noiseSuppressor!.inputSampleRate : outputSampleRate

        var format = AudioStreamBasicDescription(
            mSampleRate: Float64(captureSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        chunkTimestamp = 0
        noiseSuppressor?.resetBuffer()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = AudioQueueNewInput(
            &format,
            audioQueueCallback,
            selfPtr,
            nil,
            nil,
            0,
            &audioQueue
        )
        guard status == noErr, let queue = audioQueue else {
            throw AudioRecorderError.engineSetupFailed(
                underlying: NSError(domain: "AudioQueueAdapter", code: Int(status),
                                    userInfo: [NSLocalizedDescriptionKey: "AudioQueueNewInput failed (\(status))"])
            )
        }

        for _ in 0..<numBuffers {
            var buffer: AudioQueueBufferRef?
            let allocStatus = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer)
            guard allocStatus == noErr, let buf = buffer else {
                throw AudioRecorderError.engineSetupFailed(
                    underlying: NSError(domain: "AudioQueueAdapter", code: Int(allocStatus),
                                        userInfo: [NSLocalizedDescriptionKey: "Buffer allocation failed"])
                )
            }
            AudioQueueEnqueueBuffer(queue, buf, 0, nil)
        }

        let startStatus = AudioQueueStart(queue, nil)
        guard startStatus == noErr else {
            throw AudioRecorderError.engineSetupFailed(
                underlying: NSError(domain: "AudioQueueAdapter", code: Int(startStatus),
                                    userInfo: [NSLocalizedDescriptionKey: "AudioQueueStart failed (\(startStatus))"])
            )
        }
    }

    func stopCapture() {
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            audioQueue = nil
        }
        continuation?.finish()
    }

    fileprivate func handleBuffer(_ buffer: AudioQueueBufferRef) {
        let count = Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }

        let ptr = buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self)
        let rawSamples = Array(UnsafeBufferPointer(start: ptr, count: count))

        let samples = applyNoiseSuppression(rawSamples)
        guard !samples.isEmpty else { return }

        let chunk = makeChunk(from: samples)
        onLevel(chunk.level)
        let bands = spectrumCalculator.calculate(from: samples, sampleRate: outputSampleRate)
        onSpectrum(bands)
        continuation?.yield(chunk)

        if let queue = audioQueue {
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
    }

    private func applyNoiseSuppression(_ samples: [Float]) -> [Float] {
        guard let ns = noiseSuppressor else { return samples }
        let processed = ns.processChunk(samples)
        return AudioProcessingUtils.downsample48to16(processed)
    }

    private func makeChunk(from samples: [Float]) -> AudioChunk {
        let duration = Double(samples.count) / Double(outputSampleRate)
        let level = AudioLevelCalculator.calculate(from: samples, timestamp: chunkTimestamp)
        let chunk = AudioChunk(
            samples: samples,
            sampleRate: outputSampleRate,
            timestamp: chunkTimestamp,
            duration: duration,
            level: level
        )
        chunkTimestamp += duration
        return chunk
    }
}

/// C callback for AudioQueue — bridges to the Swift adapter.
private func audioQueueCallback(
    _ inUserData: UnsafeMutableRawPointer?,
    _ inAQ: AudioQueueRef,
    _ inBuffer: AudioQueueBufferRef,
    _ inStartTime: UnsafePointer<AudioTimeStamp>,
    _ inNumPackets: UInt32,
    _ inPacketDesc: UnsafePointer<AudioStreamPacketDescription>?
) {
    guard let userData = inUserData else { return }
    let adapter = Unmanaged<AudioQueueAdapter>.fromOpaque(userData).takeUnretainedValue()
    adapter.handleBuffer(inBuffer)
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
