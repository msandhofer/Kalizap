import Foundation
import DerFluisterer

print("=== AudioTestCLI ===")
print("Testet AudioRecorderImpl mit echtem Mikrofon.")
print("")

let recorder = AudioRecorderImpl()

// List available devices
let devices = recorder.listDevices()
print("Verfügbare Mikrofone:")
for device in devices {
    let marker = device.isDefault ? " (Default)" : ""
    print("  • \(device.name)\(marker)")
}
print("")

Task {
    do {
        try await recorder.selectDefaultDevice()
        print("✓ Default-Mikrofon ausgewählt: \(recorder.selectedDevice?.name ?? "keins")")
        print("")
        print("Starte 3-Sekunden-Aufnahme...")
        print("Sprich etwas ins Mikrofon!")
        print("")

        try await recorder.startRecording()
        print("✓ Recording gestartet (state: \(recorder.state))")

        var chunkCount = 0
        var totalSamples = 0
        var maxPeak: Float = 0

        let deadline = Date().addingTimeInterval(3.0)

        // Monitor levels in parallel
        Task {
            for await level in recorder.levelStream {
                let barLength = min(Int(level.peak * 40), 40)
                let bar = String(repeating: "█", count: barLength)
                print("  Level: \(bar) (peak: \(String(format: "%.3f", level.peak)))")
                if level.peak > maxPeak {
                    maxPeak = level.peak
                }
            }
        }

        // Collect chunks until deadline
        for try await chunk in recorder.audioStream {
            chunkCount += 1
            totalSamples += chunk.samples.count

            if Date() >= deadline {
                break
            }
        }

        await recorder.stopRecording()
        print("")
        print("✓ Recording gestoppt (state: \(recorder.state))")
        print("")
        print("=== Ergebnis ===")
        print("  Chunks empfangen: \(chunkCount)")
        print("  Samples gesamt:   \(totalSamples)")
        print("  Max Peak:         \(String(format: "%.3f", maxPeak))")

        let duration = Double(totalSamples) / 16000.0
        print("  Dauer (berechnet): \(String(format: "%.1f", duration))s")
        print("")

        // Validate
        var passed = true
        if chunkCount == 0 {
            print("✗ FAIL: Keine Chunks empfangen!")
            passed = false
        } else {
            print("✓ PASS: \(chunkCount) Chunks empfangen")
        }

        if totalSamples == 0 {
            print("✗ FAIL: Keine Samples!")
            passed = false
        } else {
            print("✓ PASS: \(totalSamples) Samples")
        }

        if duration < 2.5 {
            print("✗ FAIL: Aufnahme zu kurz (\(String(format: "%.1f", duration))s < 2.5s)")
            passed = false
        } else {
            print("✓ PASS: Aufnahmedauer plausibel")
        }

        print("")
        print(passed ? "=== ALLE TESTS BESTANDEN ===" : "=== TESTS FEHLGESCHLAGEN ===")
        exit(passed ? 0 : 1)

    } catch {
        print("✗ Fehler: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
