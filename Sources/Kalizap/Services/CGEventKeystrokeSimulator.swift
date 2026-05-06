import CoreGraphics

public final class CGEventKeystrokeSimulator: KeystrokeSimulating, @unchecked Sendable {

    public init() {}

    public func simulatePaste() async throws {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            throw KeystrokeError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public enum KeystrokeError: Error {
    case eventCreationFailed
}
