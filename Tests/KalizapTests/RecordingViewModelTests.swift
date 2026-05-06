import Testing
import Foundation
@testable import Kalizap

@Suite("RecordingViewModel")
struct RecordingViewModelTests {

    @Test("initial state is idle with mic icon")
    @MainActor
    func initialState() {
        let vm = RecordingViewModel()
        #expect(vm.isRecording == false)
        #expect(vm.menuBarIcon == "mic.fill")
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
