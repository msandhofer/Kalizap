import Foundation
import CoreGraphics
import AppKit

public final class HotkeyManagerImpl: HotkeyMonitoring, HotkeyConfiguring, @unchecked Sendable {
    private let dispatcher: HotkeyEventDispatcher
    private let accessibilityChecker: any AccessibilityChecking
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var events: AsyncStream<HotkeyEvent> { dispatcher.events }
    public private(set) var accessibilityStatus: AccessibilityStatus = .unknown
    public var isHealthy: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    public var currentConfiguration: HotkeyConfiguration { dispatcher.currentConfiguration }

    public init(
        configuration: HotkeyConfiguration = .default,
        accessibilityChecker: any AccessibilityChecking = SystemAccessibilityChecker()
    ) {
        self.dispatcher = HotkeyEventDispatcher(configuration: configuration)
        self.accessibilityChecker = accessibilityChecker
    }

    public func start() async throws {
        guard accessibilityChecker.isAccessibilityGranted() else {
            accessibilityStatus = .denied
            _ = accessibilityChecker.requestAccessibility(prompt: true)
            throw HotkeyManagerError.accessibilityDenied
        }
        accessibilityStatus = .granted
        try installEventTap()
    }

    private func installEventTap() throws {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            throw HotkeyManagerError.eventTapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        dispatcher.finish()
    }

    public func suspend() {
        dispatcher.suspend()
    }

    public func resume() {
        dispatcher.resume()
    }

    public func updateConfiguration(_ configuration: HotkeyConfiguration) {
        dispatcher.updateConfiguration(configuration)
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Capture mode: forward keypress to waiting continuation
        if captureContinuation != nil {
            if type == .keyDown || (type == .flagsChanged && Self.isModifierPressed(keyCode: keyCode, flags: event.flags)) {
                handleCapturedKey(keyCode: keyCode)
            }
            return
        }

        switch type {
        case .flagsChanged:
            let flags = event.flags
            let isPress = Self.isModifierPressed(keyCode: keyCode, flags: flags)
            if isPress {
                dispatcher.handleKeyDown(keyCode: keyCode)
            } else {
                dispatcher.handleKeyUp(keyCode: keyCode)
            }
        case .keyDown:
            dispatcher.handleKeyDown(keyCode: keyCode)
        case .keyUp:
            dispatcher.handleKeyUp(keyCode: keyCode)
        default:
            break
        }
    }

    private static func isModifierPressed(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x3A, 0x3D: return flags.contains(.maskAlternate)
        case 0x38, 0x3C: return flags.contains(.maskShift)
        case 0x3B, 0x3E: return flags.contains(.maskControl)
        case 0x37, 0x36: return flags.contains(.maskCommand)
        case 0x39:        return flags.contains(.maskAlphaShift)
        default:          return false
        }
    }

    private var captureContinuation: CheckedContinuation<HotkeyConfiguration?, Never>?

    public func captureNextKeyPress(timeout: Duration) async -> HotkeyConfiguration? {
        dispatcher.suspend()
        defer {
            captureContinuation = nil
            dispatcher.resume()
        }

        return await withCheckedContinuation { continuation in
            self.captureContinuation = continuation

            Task {
                try? await Task.sleep(for: timeout)
                // If continuation is still waiting, resume with nil (timeout)
                if let cont = self.captureContinuation {
                    self.captureContinuation = nil
                    cont.resume(returning: nil)
                }
            }
        }
    }

    fileprivate func handleCapturedKey(keyCode: UInt16) {
        guard let cont = captureContinuation else { return }
        captureContinuation = nil
        let config = HotkeyConfiguration(keyCode: keyCode, modifierFlags: 0, requiresHold: true)
        cont.resume(returning: config)
    }
}

// Top-level C function callback — avoids closure capture issues with Swift 6 Sendable checks
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManagerImpl>.fromOpaque(userInfo).takeUnretainedValue()
    manager.handleEvent(type: type, event: event)
    return Unmanaged.passRetained(event)
}

public enum HotkeyManagerError: Error, LocalizedError {
    case accessibilityDenied
    case eventTapCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission is required for global hotkey monitoring"
        case .eventTapCreationFailed:
            return "Failed to create CGEvent tap"
        }
    }
}

public struct SystemAccessibilityChecker: AccessibilityChecking {
    public init() {}

    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
