import Foundation

public final class TextInserterImpl: TextInserting, @unchecked Sendable {
    private let clipboard: any ClipboardManaging
    private let keystroke: any KeystrokeSimulating
    private let accessibility: any AccessibilityInserting
    private let appDetector: any ActiveAppDetecting
    private let restoreDelay: Duration

    public init(
        clipboard: any ClipboardManaging,
        keystroke: any KeystrokeSimulating,
        accessibility: any AccessibilityInserting,
        appDetector: any ActiveAppDetecting,
        restoreDelay: Duration = .milliseconds(80)
    ) {
        self.clipboard = clipboard
        self.keystroke = keystroke
        self.accessibility = accessibility
        self.appDetector = appDetector
        self.restoreDelay = restoreDelay
    }

    public func insert(_ text: String) async -> InsertionResult {
        let targetApp = appDetector.frontmostApp()

        // Happy path: clipboard-based insertion
        do {
            let snapshot = try await clipboard.backup()
            try await clipboard.set(text: text)
            try await keystroke.simulatePaste()
            try await Task.sleep(for: restoreDelay)
            try await clipboard.restore(from: snapshot)
            return InsertionResult(
                outcome: .inserted(method: .clipboard),
                targetApp: targetApp,
                clipboardRestored: true
            )
        } catch {
            // Fallback: try accessibility API
            if accessibility.hasTextFieldFocus() {
                do {
                    try await accessibility.insertViaAccessibility(text: text)
                    return InsertionResult(
                        outcome: .inserted(method: .accessibility),
                        targetApp: targetApp,
                        clipboardRestored: false
                    )
                } catch {
                    // Both methods failed — fall through to pendingInClipboard
                }
            }

            // Last resort: leave text in clipboard for manual paste
            try? await clipboard.set(text: text)
            return InsertionResult(
                outcome: .pendingInClipboard,
                targetApp: targetApp,
                clipboardRestored: false
            )
        }
    }
}
