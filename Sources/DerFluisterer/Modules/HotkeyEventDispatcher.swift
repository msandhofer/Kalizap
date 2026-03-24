import Foundation

final class HotkeyEventDispatcher: @unchecked Sendable {
    private(set) var currentConfiguration: HotkeyConfiguration
    private var isRecording = false
    private var isSuspended = false
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?

    let events: AsyncStream<HotkeyEvent>

    init(configuration: HotkeyConfiguration) {
        self.currentConfiguration = configuration
        var captured: AsyncStream<HotkeyEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    func suspend() {
        isSuspended = true
    }

    func resume() {
        isSuspended = false
    }

    func handleKeyDown(keyCode: UInt16) {
        guard !isSuspended else { return }
        guard keyCode == currentConfiguration.keyCode else { return }

        if currentConfiguration.requiresHold {
            guard !isRecording else { return } // ignore key repeat
            isRecording = true
            continuation?.yield(.recordingStarted)
        } else {
            // Toggle mode: each keyDown toggles state
            if isRecording {
                isRecording = false
                continuation?.yield(.recordingStopped)
            } else {
                isRecording = true
                continuation?.yield(.recordingStarted)
            }
        }
    }

    func handleKeyUp(keyCode: UInt16) {
        guard !isSuspended else { return }
        guard keyCode == currentConfiguration.keyCode else { return }

        if currentConfiguration.requiresHold {
            guard isRecording else { return }
            isRecording = false
            continuation?.yield(.recordingStopped)
        }
        // Toggle mode: keyUp is ignored
    }

    func updateConfiguration(_ newConfig: HotkeyConfiguration) {
        currentConfiguration = newConfig
    }

    func finish() {
        continuation?.finish()
    }
}
