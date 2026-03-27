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
        restoreDelay: Duration = .milliseconds(500)
    ) {
        self.clipboard = clipboard
        self.keystroke = keystroke
        self.accessibility = accessibility
        self.appDetector = appDetector
        self.restoreDelay = restoreDelay
    }

    public func insert(_ text: String) async -> InsertionResult {
        let targetApp = appDetector.frontmostApp()
        FileLog.log("insert — target: \(targetApp?.localizedName ?? "nil") (\(targetApp?.bundleIdentifier ?? "nil"))")

        // Step 1: Accessibility API — insert + verify via read-back
        if accessibility.hasTextFieldFocus() {
            do {
                try await accessibility.insertViaAccessibility(text: text)
                FileLog.log("insert — AX insert + verification succeeded")
                return .accessibility(targetApp: targetApp)
            } catch {
                FileLog.log("insert — AX failed (\(error)), falling through to clipboard")
            }
        }

        // Step 2: Clipboard + Cmd+V
        do {
            let snapshot = try await clipboard.backup()
            try await clipboard.set(text: text)
            try await keystroke.simulatePaste()
            try await Task.sleep(for: restoreDelay)
            try await clipboard.restore(from: snapshot)
            FileLog.log("insert — clipboard method succeeded")
            return .clipboard(targetApp: targetApp)
        } catch {
            FileLog.log("insert — clipboard method failed (\(error)), leaving text in clipboard")
            try? await clipboard.set(text: text)
            return .pending(targetApp: targetApp)
        }
    }
}
