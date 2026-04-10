import Foundation
import DerFluisterer

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

        Testet verschiedene restoreDelay-Werte fuer Clipboard-basierte Texteinfuegung.
        Ermittelt den minimalen Delay, bei dem der Paste zuverlaessig ankommt.

        Options:
          --app       Ziel-App: textedit (default) oder terminal
          --json      JSON-Output statt Tabelle
          --reps      Wiederholungen pro Kombination (default: 10)
          --delays    Komma-separierte Delay-Werte in ms (default: 25,50,75,100,125,150,200,300,500)
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
    ("medium", "Dies ist eine richtige Testaufnahme, die einigermassen lang ist, in der ich etwas ueber das Pferd erzaehle."),
    ("long", "Jetzt erfind ich mal wieder einen Text. Der wird aber nicht so lange sein, sondern ich werde einfach irgendwas erfinden aus meinem Kopf heraus. Z.B. was in der Bibliothek heute fuer Buecher gefunden werden, die ich dann am Schreibtisch sitzend lesen werde. Meine Brille ist dabei ganz schoen verrutscht und verwackelt, darum werden die Buchstaben ganz schoen unscharf fuer mich sein."),
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
case "terminal":
    results = runTerminalTests(delays: delays, texts: testTexts, repetitions: repetitions)
default:
    print("App '\(appName)' noch nicht unterstuetzt. Verwende 'textedit' oder 'terminal'.")
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
