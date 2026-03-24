import Foundation

struct HotkeyConfiguration: Sendable, Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt64
    var requiresHold: Bool

    static let `default` = HotkeyConfiguration(
        keyCode: 0x3D, modifierFlags: 0, requiresHold: true
    )
}

enum HotkeyEvent: Sendable {
    case recordingStarted
    case recordingStopped
}

enum AccessibilityStatus: Sendable {
    case granted, denied, unknown
}

protocol HotkeyMonitoring: AnyObject, Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    var accessibilityStatus: AccessibilityStatus { get }
    var isHealthy: Bool { get }
    func start() async throws
    func stop()
    func suspend()
    func resume()
}

protocol HotkeyConfiguring: AnyObject, Sendable {
    var currentConfiguration: HotkeyConfiguration { get }
    func updateConfiguration(_ configuration: HotkeyConfiguration)
    func captureNextKeyPress(timeout: Duration) async -> HotkeyConfiguration?
}

protocol AccessibilityChecking: Sendable {
    func isAccessibilityGranted() -> Bool
    func requestAccessibility(prompt: Bool) -> Bool
}
