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

enum TerminalScript {
    static func activate() {
        runAppleScript("""
            tell application "Terminal"
                activate
            end tell
        """)
    }

    static func readContent() -> String {
        runAppleScript("""
            tell application "Terminal"
                get contents of selected tab of front window
            end tell
        """) ?? ""
    }

    static func clearLine() {
        // Ctrl+U: kill whole line
        simulateKeystroke(virtualKey: 0x20, control: true)
    }
}

// MARK: - Terminal Test Runner

func runTerminalTests(
    delays: [Int],
    texts: [(name: String, text: String)],
    repetitions: Int
) -> [DelayTestResult] {
    var results: [DelayTestResult] = []

    TerminalScript.activate()
    Thread.sleep(forTimeInterval: 0.5)

    for delay in delays {
        for (name, text) in texts {
            var successes = 0
            print("  delay=\(delay)ms text=\(name) ", terminator: "")
            fflush(stdout)

            for _ in 0..<repetitions {
                // Clear current line
                TerminalScript.clearLine()
                Thread.sleep(forTimeInterval: 0.1)

                // Snapshot terminal content before paste
                let contentBefore = TerminalScript.readContent()

                setClipboard(text)
                Thread.sleep(forTimeInterval: 0.03)
                simulatePaste()

                Thread.sleep(forTimeInterval: Double(delay) / 1000.0)

                // Simulate restore: overwrite clipboard
                setClipboard("__RESTORED__")

                // Wait for Terminal to process paste
                Thread.sleep(forTimeInterval: 0.25)

                // Read terminal content and check for pasted text
                let contentAfter = TerminalScript.readContent()
                let newContent = String(contentAfter.dropFirst(min(contentBefore.count, contentAfter.count)))
                let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if the expected text appears in the new terminal content
                let found = newContent.contains(expected) || contentAfter.hasSuffix(expected)
                    || contentAfter.contains(expected + "\n")
                    || contentAfter.range(of: expected, options: .backwards) != nil
                    && !contentBefore.contains(expected)

                if found {
                    successes += 1
                    print(".", terminator: "")
                } else {
                    print("X", terminator: "")
                }
                fflush(stdout)

                // Clean up: Ctrl+U to clear pasted text from prompt
                TerminalScript.clearLine()
                Thread.sleep(forTimeInterval: 0.05)
            }

            let rate = Double(successes) / Double(repetitions)
            print(" \(successes)/\(repetitions)")

            results.append(DelayTestResult(
                app: "terminal",
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
