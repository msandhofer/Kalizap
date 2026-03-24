import Foundation

public struct ActiveApp: Sendable {
    public let bundleIdentifier: String
    public let localizedName: String

    public init(bundleIdentifier: String, localizedName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

public enum InsertionMethod: Sendable, Equatable {
    case clipboard, accessibility
}

public enum InsertionOutcome: Sendable, Equatable {
    case inserted(method: InsertionMethod)
    case pendingInClipboard
}

public struct InsertionResult: Sendable {
    public let outcome: InsertionOutcome
    public let targetApp: ActiveApp?
    public let clipboardRestored: Bool

    public init(outcome: InsertionOutcome, targetApp: ActiveApp?, clipboardRestored: Bool) {
        self.outcome = outcome
        self.targetApp = targetApp
        self.clipboardRestored = clipboardRestored
    }
}

public struct ClipboardSnapshot: Sendable {
    public let data: Data?

    public init(data: Data?) {
        self.data = data
    }
}

public protocol TextInserting: Sendable {
    func insert(_ text: String) async -> InsertionResult
}

public protocol ActiveAppDetecting: Sendable {
    func frontmostApp() -> ActiveApp?
}

public protocol ClipboardManaging: Sendable {
    func backup() async throws -> ClipboardSnapshot
    func set(text: String) async throws
    func restore(from snapshot: ClipboardSnapshot) async throws
}

public protocol KeystrokeSimulating: Sendable {
    func simulatePaste() async throws
}

public protocol AccessibilityInserting: Sendable {
    func hasTextFieldFocus() -> Bool
    func insertViaAccessibility(text: String) async throws
}
