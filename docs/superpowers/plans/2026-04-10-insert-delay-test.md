# Insert Delay Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automated test tool to find the minimum safe `restoreDelay` for clipboard-based text insertion.

**Architecture:** New CLI target `InsertDelayTest` depending on `Kalizap` (reuses existing clipboard/keystroke code). Iterates over delay values and text lengths, verifies pasted text via AppleScript, outputs JSON report with recommendation.

**Tech Stack:** Swift, AppKit (NSPasteboard, NSAppleScript, CGEvent), Kalizap module

---

### Task 1: Create InsertDelayTest target

**Files:**
- Modify: `Package.swift:100` (add new target after ToastTestCLI)
- Create: `Tools/InsertDelayTest/main.swift`

- [ ] **Step 1: Add target to Package.swift**

Add after the ToastTestCLI target (line 103):

```swift
        .executableTarget(
            name: "InsertDelayTest",
            dependencies: ["Kalizap"],
            path: "Tools/InsertDelayTest"
        ),
```

- [ ] **Step 2: Create main.swift skeleton**

Create `Tools/InsertDelayTest/main.swift`:

```swift
import Foundation
import Kalizap

print("=== Insert Delay Test ===")
print("Ermittelt den minimalen sicheren restoreDelay.")
exit(0)
```

- [ ] **Step 3: Verify compilation**

Run: `swift build --target InsertDelayTest 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tools/InsertDelayTest/main.swift
git commit -m "feat(#36): InsertDelayTest target skeleton"
```

---

### Task 2: Implement TextEdit paste + verify

**Files:**
- Create: `Tools/InsertDelayTest/InsertDelayTester.swift`
- Modify: `Tools/InsertDelayTest/main.swift`

- [ ] **Step 1: Create InsertDelayTester.swift**

Create `Tools/InsertDelayTest/InsertDelayTester.swift`:

```swift
import Foundation
import AppKit
import CoreGraphics
import Kalizap

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

// MARK: - Test Runner

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
    print(String(format: "%-10s %-10s %-8s %@", "Delay", "Text", "Erfolg", "Rate"))
    print(String(repeating: "-", count: 45))
    for r in report.results {
        let status = r.successRate >= 1.0 ? "OK" : "FAIL"
        print(String(format: "%-10s %-10s %-8s %.0f%%",
                      "\(r.delayMs)ms", r.textLength,
                      "\(r.successes)/\(r.runs) \(status)", r.successRate * 100))
    }
    print()
    if let safe = report.recommendation.minSafeDelayMs {
        print("Empfehlung: minimaler sicherer Delay = \(safe)ms")
    } else {
        print("WARNUNG: kein Delay erreichte 100% Erfolgsrate")
    }
}
```

- [ ] **Step 2: Wire up main.swift**

Replace `Tools/InsertDelayTest/main.swift`:

```swift
import Foundation
import Kalizap

// MARK: - Argument Parsing

let args = CommandLine.arguments
var appName = "textedit"
var jsonOutput = false
var repetitions = 10
var customDelays: [Int]? = nil

var i = 1
while i < args.count {
    switch args[i] {
    case "--app":     i += 1; appName = args[i].lowercased()
    case "--json":    jsonOutput = true
    case "--reps":    i += 1; repetitions = Int(args[i]) ?? 10
    case "--delays":  i += 1; customDelays = args[i].split(separator: ",").compactMap { Int($0) }
    case "--help":
        print("""
        Usage: InsertDelayTest [--app textedit|terminal] [--json] [--reps N] [--delays 25,50,100,...]
        """)
        exit(0)
    default: break
    }
    i += 1
}

let delays = customDelays ?? [25, 50, 75, 100, 125, 150, 200, 300, 500]

// MARK: - Test Texts

let testTexts: [(name: String, text: String)] = [
    ("short", "kurz"),
    ("medium", "Dies ist eine richtige Testaufnahme, die einigermaßen lang ist, in der ich etwas über das Pferd erzähle."),
    ("long", "Jetzt erfind ich mal wieder einen Text. Der wird aber nicht so lange sein, sondern ich werde einfach irgendwas erfinden aus meinem Kopf heraus. Z.B. was in der Bibliothek heute für Bücher gefunden werden, die ich dann am Schreibtisch sitzend lesen werde. Meine Brille ist dabei ganz schön verrutscht und verwackelt, darum werden die Buchstaben ganz schön unscharf für mich sein."),
]

// MARK: - Run

print("=== Insert Delay Test ===")
print("App:         \(appName)")
print("Delays:      \(delays.map { "\($0)ms" }.joined(separator: ", "))")
print("Reps:        \(repetitions)")
print("Texte:       \(testTexts.map { "\($0.name) (\($0.text.count) chars)" }.joined(separator: ", "))")
print()

let results: [DelayTestResult]

switch appName {
case "textedit":
    results = runTextEditTests(delays: delays, texts: testTexts, repetitions: repetitions)
default:
    print("App '\(appName)' noch nicht unterstuetzt. Verwende 'textedit'.")
    exit(1)
}

let report = buildReport(app: appName, results: results, delays: delays)

if jsonOutput {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let json = try? encoder.encode(report), let str = String(data: json, encoding: .utf8) {
        print(str)
    }
} else {
    printReport(report)
}
```

- [ ] **Step 3: Verify compilation**

Run: `swift build --target InsertDelayTest 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Quick manual smoke test**

Run: `swift run InsertDelayTest --app textedit --delays 200 --reps 1`

Expected: Opens TextEdit, pastes "kurz", verifies, prints result. One dot per success.

- [ ] **Step 5: Commit**

```bash
git add Tools/InsertDelayTest/InsertDelayTester.swift Tools/InsertDelayTest/main.swift
git commit -m "feat(#36): InsertDelayTest TextEdit paste+verify implementation"
```

---

### Task 3: Run full TextEdit test suite

**Files:** None (execution only)

- [ ] **Step 1: Run full suite**

Run: `swift run InsertDelayTest --app textedit --reps 10 --json 2>/dev/null | tee Tests/Testdaten/insert-delay-textedit.json`

Expected: ~270 test runs (9 delays x 3 texts x 10 reps). Takes ~5-8 minutes.

- [ ] **Step 2: Analyze results**

Check JSON output for:
- Minimum delay where ALL text lengths have 100% success
- Whether short texts need less delay than long texts
- Whether there is a sharp cutoff or gradual degradation

- [ ] **Step 3: Commit results**

```bash
git add Tests/Testdaten/insert-delay-textedit.json
git commit -m "test(#36): TextEdit insert delay test results"
```

---

### Task 4: Add Terminal support

**Files:**
- Modify: `Tools/InsertDelayTest/InsertDelayTester.swift`
- Modify: `Tools/InsertDelayTest/main.swift`

**Note:** Terminal verification is harder than TextEdit. The approach: paste text at shell prompt, then use `pbpaste`-style verification or AppleScript `contents` to check the result. Exact implementation depends on TextEdit test outcomes — if delays >=100ms all pass, Terminal likely behaves similarly.

- [ ] **Step 1: Implement Terminal test runner**

Add to `InsertDelayTester.swift`:

```swift
enum TerminalScript {
    static func activate() {
        runAppleScript("""
            tell application "Terminal"
                activate
            end tell
        """)
    }

    static func clearLine() {
        // Ctrl+U: kill line, Ctrl+K: kill to end
        simulateKeystroke(virtualKey: 0x20, control: true)  // U
    }

    static func readContent() -> String {
        runAppleScript("""
            tell application "Terminal"
                get contents of selected tab of front window
            end tell
        """) ?? ""
    }
}

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
                TerminalScript.clearLine()
                Thread.sleep(forTimeInterval: 0.1)

                // Snapshot terminal content before paste
                let contentBefore = TerminalScript.readContent()

                setClipboard(text)
                Thread.sleep(forTimeInterval: 0.03)
                simulatePaste()

                Thread.sleep(forTimeInterval: Double(delay) / 1000.0)

                setClipboard("__RESTORED__")

                Thread.sleep(forTimeInterval: 0.25)

                // Check if terminal content now includes the test text
                let contentAfter = TerminalScript.readContent()
                let newContent = String(contentAfter.dropFirst(contentBefore.count))

                let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let found = newContent.contains(expected)

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
```

- [ ] **Step 2: Wire up Terminal in main.swift**

In main.swift, extend the switch:

```swift
case "terminal":
    results = runTerminalTests(delays: delays, texts: testTexts, repetitions: repetitions)
```

- [ ] **Step 3: Verify compilation + smoke test**

Run: `swift run InsertDelayTest --app terminal --delays 200 --reps 1`
Expected: Activates Terminal, pastes "kurz", verifies via AppleScript contents.

- [ ] **Step 4: Run full Terminal suite**

Run: `swift run InsertDelayTest --app terminal --reps 10 --json 2>/dev/null | tee Tests/Testdaten/insert-delay-terminal.json`

- [ ] **Step 5: Commit**

```bash
git add Tools/InsertDelayTest/ Tests/Testdaten/insert-delay-terminal.json
git commit -m "feat(#36): Terminal support for InsertDelayTest + results"
```
