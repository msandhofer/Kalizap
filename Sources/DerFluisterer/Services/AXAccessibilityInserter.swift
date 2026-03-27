import AppKit

public final class AXAccessibilityInserter: AccessibilityInserting, @unchecked Sendable {

    public init() {}

    public func hasTextFieldFocus() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return false }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        guard let roleString = role as? String else { return false }

        let textRoles = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        return textRoles.contains(roleString)
    }

    public func insertViaAccessibility(text: String) async throws {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else {
            throw AccessibilityInsertionError.noFocusedElement
        }

        let axElement = element as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard setResult == .success else {
            throw AccessibilityInsertionError.setValueFailed(setResult)
        }

        // Verify via read-back: some apps (e.g. iTerm2) report success but silently discard the write
        var value: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value)
        let fieldContent = value as? String
        guard fieldContent?.contains(text) == true else {
            throw AccessibilityInsertionError.verificationFailed
        }
    }
}

public enum AccessibilityInsertionError: Error {
    case noFocusedElement
    case setValueFailed(AXError)
    case verificationFailed
}
