import Foundation

protocol SoundPlaying: Sendable {
    func playStartSound() async
    func playStopSound() async
}

struct PipelineDependencies {
    let hotkey: any HotkeyMonitoring
    let recorder: any AudioCapturing
    let metering: any AudioLevelMetering
    let transcriber: any TranscriptionEngine
    let corrector: any TextCorrecting
    let inserter: any TextInserting
    let appDetector: any ActiveAppDetecting
    let store: any DictationStoring
    let sound: any SoundPlaying
}
