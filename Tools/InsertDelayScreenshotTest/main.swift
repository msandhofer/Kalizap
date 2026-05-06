import Foundation
import AppKit
import CoreGraphics
import Kalizap

// MARK: - Argument Parsing

let args = CommandLine.arguments
var appName = "ghostty"
var customDelays: [Int]? = nil

var i = 1
while i < args.count {
    switch args[i] {
    case "--app":    i += 1; appName = args[i].lowercased()
    case "--delays": i += 1; customDelays = args[i].split(separator: ",").compactMap { Int($0) }
    case "--help":
        print("""
        Usage: InsertDelayScreenshotTest [--app ghostty|iterm] [--delays 150,200,250]

        Screenshot-basierter Insert-Delay-Test fuer Apps ohne AppleScript-Support.
        Testet nur short + long Text, 1 Wiederholung, speichert Screenshots.

        Options:
          --app       Ziel-App (default: ghostty)
          --delays    Komma-separierte Delay-Werte in ms (default: 150,200,250)
        """)
        exit(0)
    default: break
    }
    i += 1
}

let delays = customDelays ?? [150, 200, 250]

let testTexts: [(name: String, text: String)] = [
    ("short", "kurz"),
    ("long", "Jetzt erfind ich mal wieder einen Text. Der wird aber nicht so lange sein, sondern ich werde einfach irgendwas erfinden aus meinem Kopf heraus. Z.B. was in der Bibliothek heute fuer Buecher gefunden werden, die ich dann am Schreibtisch sitzend lesen werde. Meine Brille ist dabei ganz schoen verrutscht und verwackelt, darum werden die Buchstaben ganz schoen unscharf fuer mich sein."),
]

let projectRoot = FileManager.default.currentDirectoryPath
let screenshotDir = projectRoot + "/Tools/InsertDelayScreenshotTest/screenshots"

// MARK: - Window Capture

func findWindowID(appName: String) -> CGWindowID? {
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String,
              let windowID = window[kCGWindowNumber as String] as? Int,
              let layer = window[kCGWindowLayer as String] as? Int,
              layer == 0
        else { continue }

        if ownerName.lowercased().contains(appName.lowercased()) {
            return CGWindowID(windowID)
        }
    }
    return nil
}

func captureScreen(to path: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", path]
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
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

@discardableResult
func runAppleScript(_ source: String) -> String? {
    let script = NSAppleScript(source: source)
    var error: NSDictionary?
    let result = script?.executeAndReturnError(&error)
    return result?.stringValue
}

// MARK: - Main

print("=== Insert Delay Screenshot Test ===")
print("App:         \(appName)")
print("Delays:      \(delays.map { "\($0)ms" }.joined(separator: ", "))")
print("Texte:       \(testTexts.map { "\($0.name) (\($0.text.count) chars)" }.joined(separator: ", "))")
print("Screenshots: \(screenshotDir)")
print()

// Clean old screenshots for this app
let fm = FileManager.default
if let files = try? fm.contentsOfDirectory(atPath: screenshotDir) {
    for file in files where file.hasPrefix(appName) && file.hasSuffix(".png") {
        try? fm.removeItem(atPath: screenshotDir + "/" + file)
    }
}

// Activate app
let activateAppName: String
switch appName {
case "iterm", "iterm2": activateAppName = "iTerm2"
case "ghostty":         activateAppName = "Ghostty"
case "terminal":        activateAppName = "Terminal"
default:                activateAppName = appName
}

runAppleScript("tell application \"\(activateAppName)\" to activate")
Thread.sleep(forTimeInterval: 0.5)

// Find window
let searchName = appName == "iterm" ? "iterm2" : appName
guard let windowID = findWindowID(appName: searchName) else {
    print("FEHLER: \(activateAppName)-Fenster nicht gefunden. Ist die App geoeffnet?")
    exit(1)
}
print("\(activateAppName) WindowID: \(windowID)")
print()

// Run tests
for delay in delays {
    for (name, text) in testTexts {
        let filename = String(format: "%@_%03dms_%@.png", appName, delay, name)
        let filepath = screenshotDir + "/" + filename
        print("  Test: delay=\(delay)ms text=\(name) ... ", terminator: "")
        fflush(stdout)

        // Clear line
        simulateKeystroke(virtualKey: 0x20, control: true) // Ctrl+U
        Thread.sleep(forTimeInterval: 0.15)

        // Set clipboard and paste
        setClipboard(text)
        Thread.sleep(forTimeInterval: 0.03)
        simulatePaste()

        // Wait the test delay
        Thread.sleep(forTimeInterval: Double(delay) / 1000.0)

        // Simulate restore: overwrite clipboard
        setClipboard("__RESTORED__")

        // Wait for app to fully process
        Thread.sleep(forTimeInterval: 0.3)

        // Capture screenshot
        if captureScreen(to: filepath) {
            print(filename)
        } else {
            print("SCREENSHOT FEHLGESCHLAGEN")
        }

        // Clean up: Ctrl+U
        simulateKeystroke(virtualKey: 0x20, control: true)
        Thread.sleep(forTimeInterval: 0.1)
    }
}

print()
print("Fertig. \(delays.count * testTexts.count) Screenshots in:")
print("  \(screenshotDir)")
