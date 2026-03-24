import Foundation
import DerFluisterer

print("=== TextInsertTestCLI ===")
print("Testet Text-Einfügung via Clipboard + Cmd+V.")
print("")
print("WICHTIG: Accessibility-Berechtigung muss erteilt sein!")
print("  → Systemeinstellungen > Datenschutz > Bedienungshilfen")
print("")

let clipboardManager = NSPasteboardClipboardManager()
let keystrokeSimulator = CGEventKeystrokeSimulator()
let accessibilityInserter = AXAccessibilityInserter()
let appDetector = NSWorkspaceAppDetector()

let inserter = TextInserterImpl(
    clipboard: clipboardManager,
    keystroke: keystrokeSimulator,
    accessibility: accessibilityInserter,
    appDetector: appDetector,
    restoreDelay: .milliseconds(100)
)

Task {
    // 1. Active App Detection
    if let app = appDetector.frontmostApp() {
        print("✓ Aktive App: \(app.localizedName) (\(app.bundleIdentifier))")
    } else {
        print("✗ Keine aktive App erkannt")
    }
    print("")

    // 2. Clipboard Backup/Restore Test
    print("Test 1: Clipboard Backup/Restore")
    do {
        let snapshot = try await clipboardManager.backup()
        print("  ✓ Clipboard gesichert (\(snapshot.data?.count ?? 0) bytes)")
        try await clipboardManager.set(text: "TEST_TEXT_INSERTER")
        print("  ✓ Test-Text in Clipboard gesetzt")
        try await clipboardManager.restore(from: snapshot)
        print("  ✓ Clipboard wiederhergestellt")
    } catch {
        print("  ✗ Clipboard-Fehler: \(error)")
    }
    print("")

    // 3. Accessibility Check
    print("Test 2: Accessibility Text-Feld Erkennung")
    let hasTextField = accessibilityInserter.hasTextFieldFocus()
    print("  Textfeld erkannt: \(hasTextField ? "ja" : "nein")")
    print("")

    // 4. Full Insertion Test
    print("Test 3: Vollständige Text-Einfügung")
    print("  Du hast 3 Sekunden — klicke in ein Textfeld!")
    print("  (z.B. TextEdit, Terminal, Browser-Suchleiste)")
    print("")

    for i in (1...3).reversed() {
        print("  \(i)...")
        try? await Task.sleep(for: .seconds(1))
    }

    let testText = "Hallo von DerFlüsterer! 🎤"
    print("  Füge ein: \"\(testText)\"")

    let result = await inserter.insert(testText)

    print("")
    print("=== Ergebnis ===")
    switch result.outcome {
    case .inserted(let method):
        print("  ✓ Text eingefügt via: \(method)")
    case .pendingInClipboard:
        print("  ⚠ Text liegt im Clipboard — drücke Cmd+V zum Einfügen")
    }
    print("  Ziel-App: \(result.targetApp?.localizedName ?? "unbekannt")")
    print("  Clipboard restored: \(result.clipboardRestored)")
    print("")

    exit(0)
}

RunLoop.main.run()
