import Foundation

public protocol AudioEngineProviding: Sendable {
    var audioStream: AsyncThrowingStream<AudioChunk, Error> { get }
    func startCapture() throws
    func stopCapture()
}

public final class AudioSessionCoordinator: @unchecked Sendable {
    private let engine: AudioEngineProviding
    public private(set) var state: AudioRecorderState = .idle

    public init(engine: AudioEngineProviding) {
        self.engine = engine
    }

    public func startRecording() async throws {
        guard state == .idle else { return }
        try engine.startCapture()
        state = .recording
    }

    public func stopRecording() async {
        guard state == .recording else { return }
        engine.stopCapture()
        state = .idle
    }

    public var audioStream: AsyncThrowingStream<AudioChunk, Error> {
        engine.audioStream
    }
}
