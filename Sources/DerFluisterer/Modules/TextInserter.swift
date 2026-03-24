import Foundation

struct ActiveApp: Sendable {
    let bundleIdentifier: String
    let localizedName: String
}

enum InsertionMethod: Sendable {
    case clipboard, accessibility
}

enum InsertionOutcome: Sendable {
    case inserted(method: InsertionMethod)
    case pendingInClipboard
}

struct InsertionResult: Sendable {
    let outcome: InsertionOutcome
    let targetApp: ActiveApp?
    let clipboardRestored: Bool
}

struct ClipboardSnapshot: Sendable {
    let data: Data?
}

protocol TextInserting: Sendable {
    func insert(_ text: String) async -> InsertionResult
}

protocol ActiveAppDetecting: Sendable {
    func frontmostApp() -> ActiveApp?
}

protocol ClipboardManaging: Sendable {
    func backup() async throws -> ClipboardSnapshot
    func set(text: String) async throws
    func restore(from snapshot: ClipboardSnapshot) async throws
}

protocol KeystrokeSimulating: Sendable {
    func simulatePaste() async throws
}

protocol AccessibilityInserting: Sendable {
    func insertViaAccessibility(text: String) async throws
}
