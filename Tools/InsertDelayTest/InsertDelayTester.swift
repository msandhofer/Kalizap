import Foundation
import AppKit
import CoreGraphics
import DerFluisterer

// MARK: - Types

struct DelayTestResult: Codable {
    let app: String
    let textLength: String
    let textChars: Int
    let delayMs: Int
    let runs: Int
    let successes: Int
    let successRate: Double
}

struct DelayTestReport: Codable {
    let app: String
    let timestamp: String
    let results: [DelayTestResult]
    let recommendation: Recommendation

    struct Recommendation: Codable {
        let minSafeDelayMs: Int?
        let notes: String
    }
}

// MARK: - AppleScript Helpers

enum TextEditScript {
    static func activate() {
        runAppleScript("""
            tell application "TextEdit"
                activate
                if (count of documents) = 0 then make new document
            end tell
        """)
    }

    static func clear() {
        runAppleScript("""
            tell application "TextEdit"
                set text of document 1 to ""
            end tell
        """)
    }

    static func readContent() -> String {
        runAppleScript("""
            tell application "TextEdit"
                get text of document 1
            end tell
        """) ?? ""
    }
}

@discardableResult
func runAppleScript(_ source: String) -> String? {
    let script = NSAppleScript(source: source)
    var error: NSDictionary?
    let result = script?.executeAndReturnError(&error)
    if let error {
        FileLog.log("AppleScript error: \(error)")
    }
    return result?.stringValue
}

// MARK: - Paste Simulation

func setClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    else { return }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

// MARK: - TextEdit Test Runner

func runTextEditTests(
    delays: [Int],
    texts: [(name: String, text: String)],
    repetitions: Int
) -> [DelayTestResult] {
    var results: [DelayTestResult] = []

    TextEditScript.activate()
    Thread.sleep(forTimeInterval: 0.5)

    for delay in delays {
        for (name, text) in texts {
            var successes = 0
            print("  delay=\(delay)ms text=\(name) ", terminator: "")
            fflush(stdout)

            for _ in 0..<repetitions {
                TextEditScript.clear()
                Thread.sleep(forTimeInterval: 0.15)

                setClipboard(text)
                Thread.sleep(forTimeInterval: 0.03)
                simulatePaste()

                Thread.sleep(forTimeInterval: Double(delay) / 1000.0)

                // Simulate restore: overwrite clipboard
                setClipboard("__RESTORED__")

                // Wait for TextEdit to process paste
                Thread.sleep(forTimeInterval: 0.25)

                let inserted = TextEditScript.readContent()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let expected = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if inserted == expected {
                    successes += 1
                    print(".", terminator: "")
                } else {
                    print("X", terminator: "")
                }
                fflush(stdout)
            }

            let rate = Double(successes) / Double(repetitions)
            print(" \(successes)/\(repetitions)")

            results.append(DelayTestResult(
                app: "textedit",
                textLength: name,
                textChars: text.count,
                delayMs: delay,
                runs: repetitions,
                successes: successes,
                successRate: rate
            ))
        }
    }

    return results
}

// MARK: - Terminal Helpers

func simulateKeystroke(virtualKey: CGKeyCode, control: Bool = false) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
    else { return }
    if control {
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

// MARK: - Generic Terminal App Config

struct TerminalAppConfig {
    let name: String
    let activateScript: String
    let readContentScript: String

    static let terminal = TerminalAppConfig(
        name: "terminal",
        activateScript: """
            tell application "Terminal"
                activate
            end tell
        """,
        readContentScript: """
            tell application "Terminal"
                get contents of selected tab of front window
            end tell
        """
    )

    static let iterm = TerminalAppConfig(
        name: "iterm",
        activateScript: """
            tell application "iTerm2"
                activate
            end tell
        """,
        readContentScript: """
            tell application "iTerm2"
                tell current session of current tab of current window
                    get contents
                end tell
            end tell
        """
    )

    static let ghostty = TerminalAppConfig(
        name: "ghostty",
        activateScript: """
            tell application "Ghostty"
                activate
            end tell
        """,
        // Ghostty has no native AppleScript — use System Events UI scripting
        readContentScript: """
            tell application "System Events"
                tell process "ghostty"
                    set frontWindow to window 1
                    set uiElems to entire contents of frontWindow
                    set result to ""
                    repeat with elem in uiElems
                        try
                            set v to value of elem
                            if v is not missing value and class of v is text then
                                set result to result & v
                            end if
                        end try
                    end repeat
                    return result
                end tell
            end tell
        """
    )
}

// MARK: - Generic Terminal Test Runner

func runGenericTerminalTests(
    config: TerminalAppConfig,
    delays: [Int],
    texts: [(name: String, text: String)],
    repetitions: Int
) -> [DelayTestResult] {
    var results: [DelayTestResult] = []

    runAppleScript(config.activateScript)
    Thread.sleep(forTimeInterval: 0.5)

    // Verify we can read content
    let probe = runAppleScript(config.readContentScript)
    if probe == nil {
        print("  WARNUNG: AppleScript readContent fuer \(config.name) liefert nil.")
        print("  Versuche trotzdem fortzufahren...")
    }

    for delay in delays {
        for (name, text) in texts {
            var successes = 0
            print("  delay=\(delay)ms text=\(name) ", terminator: "")
            fflush(stdout)

            for _ in 0..<repetitions {
                // Clear current line (Ctrl+U)
                simulateKeystroke(virtualKey: 0x20, control: true)
                Thread.sleep(forTimeInterval: 0.1)

                // Snapshot content before paste
                let contentBefore = runAppleScript(config.readContentScript) ?? ""

                setClipboard(text)
                Thread.sleep(forTimeInterval: 0.03)
                simulatePaste()

                Thread.sleep(forTimeInterval: Double(delay) / 1000.0)

                // Simulate restore: overwrite clipboard
                setClipboard("__RESTORED__")

                // Wait for app to process paste
                Thread.sleep(forTimeInterval: 0.25)

                // Read content and check for pasted text
                let contentAfter = runAppleScript(config.readContentScript) ?? ""
                let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if expected text newly appears in terminal content
                let appearedAfter = contentAfter.contains(expected)
                let wasAlreadyThere = contentBefore.contains(expected)
                let found = appearedAfter && !wasAlreadyThere

                if found {
                    successes += 1
                    print(".", terminator: "")
                } else {
                    print("X", terminator: "")
                }
                fflush(stdout)

                // Clean up: Ctrl+U
                simulateKeystroke(virtualKey: 0x20, control: true)
                Thread.sleep(forTimeInterval: 0.05)
            }

            let rate = Double(successes) / Double(repetitions)
            print(" \(successes)/\(repetitions)")

            results.append(DelayTestResult(
                app: config.name,
                textLength: name,
                textChars: text.count,
                delayMs: delay,
                runs: repetitions,
                successes: successes,
                successRate: rate
            ))
        }
    }

    return results
}

// Convenience wrappers
func runTerminalTests(delays: [Int], texts: [(name: String, text: String)], repetitions: Int) -> [DelayTestResult] {
    runGenericTerminalTests(config: .terminal, delays: delays, texts: texts, repetitions: repetitions)
}

func runITermTests(delays: [Int], texts: [(name: String, text: String)], repetitions: Int) -> [DelayTestResult] {
    runGenericTerminalTests(config: .iterm, delays: delays, texts: texts, repetitions: repetitions)
}

func runGhosttyTests(delays: [Int], texts: [(name: String, text: String)], repetitions: Int) -> [DelayTestResult] {
    runGenericTerminalTests(config: .ghostty, delays: delays, texts: texts, repetitions: repetitions)
}

// MARK: - Report

func buildReport(app: String, results: [DelayTestResult], delays: [Int]) -> DelayTestReport {
    let minSafe = delays.first { delay in
        results
            .filter { $0.delayMs == delay }
            .allSatisfy { $0.successRate >= 1.0 }
    }

    let formatter = ISO8601DateFormatter()
    return DelayTestReport(
        app: app,
        timestamp: formatter.string(from: Date()),
        results: results,
        recommendation: .init(
            minSafeDelayMs: minSafe,
            notes: minSafe.map {
                "100% Erfolg ab \($0)ms fuer alle Textlaengen"
            } ?? "Kein Delay erreichte 100% fuer alle Textlaengen"
        )
    )
}

func printReport(_ report: DelayTestReport) {
    print()
    print("=== Ergebnis: \(report.app) ===")
    print()
    let header = "Delay".padding(toLength: 10, withPad: " ", startingAt: 0)
        + "Text".padding(toLength: 10, withPad: " ", startingAt: 0)
        + "Erfolg".padding(toLength: 14, withPad: " ", startingAt: 0)
        + "Rate"
    print(header)
    print(String(repeating: "-", count: 48))
    for r in report.results {
        let status = r.successRate >= 1.0 ? "OK" : "FAIL"
        let line = "\(r.delayMs)ms".padding(toLength: 10, withPad: " ", startingAt: 0)
            + r.textLength.padding(toLength: 10, withPad: " ", startingAt: 0)
            + "\(r.successes)/\(r.runs) \(status)".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "\(Int(r.successRate * 100))%"
        print(line)
    }
    print()
    if let safe = report.recommendation.minSafeDelayMs {
        print("Empfehlung: minimaler sicherer Delay = \(safe)ms")
    } else {
        print("WARNUNG: kein Delay erreichte 100% Erfolgsrate")
    }
}
