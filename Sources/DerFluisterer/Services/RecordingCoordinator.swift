import Foundation

public protocol RecordingControlling: Sendable {
    func startRecording() async throws
    func stopRecording() async
}

@MainActor
public final class RecordingCoordinator {
    private let hotkeyEvents: AsyncStream<HotkeyEvent>
    private let recorder: RecordingControlling
    private let soundPlayer: SoundPlayer
    private let viewModel: RecordingViewModel

    public init(
        hotkeyEvents: AsyncStream<HotkeyEvent>,
        recorder: RecordingControlling,
        soundPlayer: SoundPlayer,
        viewModel: RecordingViewModel
    ) {
        self.hotkeyEvents = hotkeyEvents
        self.recorder = recorder
        self.soundPlayer = soundPlayer
        self.viewModel = viewModel
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
                await recorder.stopRecording()
                soundPlayer.playRecordingStopped()
                viewModel.stopRecording()
            }
        }
    }
}
