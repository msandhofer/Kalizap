import Foundation

public protocol RecordingControlling: Sendable {
    func startRecording() async throws
    func stopAndCollectBuffer() async -> CollectedAudioBuffer
}

public protocol TranscriptionHandling: Sendable {
    func transcribe(buffer: CollectedAudioBuffer, config: TranscriptionConfig) async throws -> FinalTranscription
}

@MainActor
public final class RecordingCoordinator {
    private let hotkeyEvents: AsyncStream<HotkeyEvent>
    private let recorder: RecordingControlling
    private let soundPlayer: SoundPlayer
    public let viewModel: RecordingViewModel
    private let transcriptionHandler: TranscriptionHandling?
    public private(set) var lastTranscription: FinalTranscription?
    public var transcriptionConfig = TranscriptionConfig()

    public init(
        hotkeyEvents: AsyncStream<HotkeyEvent>,
        recorder: RecordingControlling,
        soundPlayer: SoundPlayer,
        viewModel: RecordingViewModel,
        transcriptionHandler: TranscriptionHandling? = nil
    ) {
        self.hotkeyEvents = hotkeyEvents
        self.recorder = recorder
        self.soundPlayer = soundPlayer
        self.viewModel = viewModel
        self.transcriptionHandler = transcriptionHandler
    }

    public func run() async {
        for await event in hotkeyEvents {
            switch event {
            case .recordingStarted:
                do {
                    try await recorder.startRecording()
                    soundPlayer.playRecordingStarted()
                    viewModel.startRecording()
                } catch {
                    // Recording failed to start — don't update UI
                }
            case .recordingStopped:
                let buffer = await recorder.stopAndCollectBuffer()
                soundPlayer.playRecordingStopped()
                viewModel.stopRecording()
                await performTranscription(buffer: buffer)
            }
        }
    }

    private func performTranscription(buffer: CollectedAudioBuffer) async {
        guard let handler = transcriptionHandler, !buffer.samples.isEmpty else { return }
        do {
            let result = try await handler.transcribe(buffer: buffer, config: transcriptionConfig)
            lastTranscription = result
            print("[DerFlüsterer] Transkription: \(result.text) (\(result.processingTime))")
        } catch {
            print("[DerFlüsterer] Transkription fehlgeschlagen: \(error)")
        }
    }
}
