import Foundation
import DerFluisterer

print("=== HotkeyTestCLI ===")
print("Testet den HotkeyManager mit echtem CGEvent-Tap.")
print("")

// Check accessibility
let checker = SystemAccessibilityChecker()
if checker.isAccessibilityGranted() {
    print("✓ Accessibility-Permission vorhanden")
} else {
    print("✗ Accessibility-Permission fehlt!")
    print("  → Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen")
    print("  → Terminal (oder den Prozess, der dieses Tool ausführt) aktivieren")
    print("")
    _ = checker.requestAccessibility(prompt: true)
    print("Dialog sollte erschienen sein. Nach Aktivierung erneut starten.")
    exit(1)
}

print("")
print("Starte HotkeyManager (Default: rechte Option-Taste, Push-to-Talk)...")
print("Drücke die rechte Option-Taste zum Testen.")
print("Ctrl+C zum Beenden.")
print("")

let manager = HotkeyManagerImpl(configuration: .default)

Task {
    do {
        try await manager.start()
        print("✓ CGEvent-Tap aktiv (isHealthy: \(manager.isHealthy))")
        print("")

        for await event in manager.events {
            switch event {
            case .recordingStarted:
                print("🎙️  Recording STARTED  (\(Date().formatted(date: .omitted, time: .standard)))")
            case .recordingStopped:
                print("⏹️  Recording STOPPED  (\(Date().formatted(date: .omitted, time: .standard)))")
            }
        }
    } catch {
        print("✗ Fehler: \(error.localizedDescription)")
        exit(1)
    }
}

// Keep the process alive
RunLoop.main.run()
