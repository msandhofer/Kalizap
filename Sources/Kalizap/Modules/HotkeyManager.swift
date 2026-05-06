import Foundation

public struct HotkeyConfiguration: Sendable, Codable, Equatable {
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var requiresHold: Bool

    public static let `default` = HotkeyConfiguration(
        keyCode: 0x3D, modifierFlags: 0, requiresHold: true
    )

    public init(keyCode: UInt16, modifierFlags: UInt64, requiresHold: Bool) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.requiresHold = requiresHold
    }
}

public enum HotkeyEvent: Sendable, Equatable {
    case recordingStarted
    case recordingStopped
}

public enum AccessibilityStatus: Sendable {
    case granted, denied, unknown
}

public protocol HotkeyMonitoring: AnyObject, Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    var accessibilityStatus: AccessibilityStatus { get }
    var isHealthy: Bool { get }
    func start() async throws
    func stop()
    func suspend()
    func resume()
}

public protocol HotkeyConfiguring: AnyObject, Sendable {
    var currentConfiguration: HotkeyConfiguration { get }
    func updateConfiguration(_ configuration: HotkeyConfiguration)
    func captureNextKeyPress(timeout: Duration) async -> HotkeyConfiguration?
}

public protocol AccessibilityChecking: Sendable {
    func isAccessibilityGranted() -> Bool
    func requestAccessibility(prompt: Bool) -> Bool
}
