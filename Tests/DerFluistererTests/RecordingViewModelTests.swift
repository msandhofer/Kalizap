import Testing
import Foundation
@testable import DerFluisterer

@Suite("RecordingViewModel")
struct RecordingViewModelTests {

    @Test("initial state is idle with mic icon")
    @MainActor
    func initialState() {
        let vm = RecordingViewModel()
        #expect(vm.isRecording == false)
        #expect(vm.menuBarIcon == "mic.fill")
        #expect(vm.waveformLevels.isEmpty)
    }

    @Test("recording state shows waveform icon")
    @MainActor
    func recordingState() {
        let vm = RecordingViewModel()
        vm.startRecording()
        #expect(vm.isRecording == true)
        #expect(vm.menuBarIcon == "waveform")
    }

    @Test("stop recording returns to mic icon")
    @MainActor
    func stopRecording() {
        let vm = RecordingViewModel()
        vm.startRecording()
        vm.stopRecording()
        #expect(vm.isRecording == false)
        #expect(vm.menuBarIcon == "mic.fill")
        #expect(vm.waveformLevels.isEmpty)
    }

    @Test("updateLevel adds to waveform levels")
    @MainActor
    func updateLevel() {
        let vm = RecordingViewModel()
        vm.startRecording()
        vm.updateLevel(AudioLevel(average: 0.5, peak: 0.8, timestamp: 0))
        #expect(vm.waveformLevels.count == 1)
        #expect(vm.waveformLevels[0] == 0.8)
    }

    @Test("waveform levels are capped at maxBars")
    @MainActor
    func waveformCapped() {
        let vm = RecordingViewModel(maxWaveformBars: 3)
        vm.startRecording()
        vm.updateLevel(AudioLevel(average: 0.1, peak: 0.1, timestamp: 0))
        vm.updateLevel(AudioLevel(average: 0.2, peak: 0.2, timestamp: 0))
        vm.updateLevel(AudioLevel(average: 0.3, peak: 0.3, timestamp: 0))
        vm.updateLevel(AudioLevel(average: 0.4, peak: 0.4, timestamp: 0))
        #expect(vm.waveformLevels.count == 3)
        // oldest dropped, newest kept
        #expect(vm.waveformLevels == [0.2, 0.3, 0.4])
    }

    @Test("updateLevel ignored when not recording")
    @MainActor
    func updateLevelWhenIdle() {
        let vm = RecordingViewModel()
        vm.updateLevel(AudioLevel(average: 0.5, peak: 0.8, timestamp: 0))
        #expect(vm.waveformLevels.isEmpty)
    }

    @Test("isPulsing follows recording state")
    @MainActor
    func pulsing() {
        let vm = RecordingViewModel()
        #expect(vm.isPulsing == false)
        vm.startRecording()
        #expect(vm.isPulsing == true)
        vm.stopRecording()
        #expect(vm.isPulsing == false)
    }
}
