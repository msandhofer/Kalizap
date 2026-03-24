import Foundation
import DerFluisterer

print("=== CorrectorTestCLI ===")
print("Testet Claude Haiku Textkorrektur mit echtem API-Call.")
print("")

let keychain = KeychainService()
let apiKeyProvider: @Sendable () throws -> String = {
    try keychain.retrieve(for: "anthropic-api-key")
}

// Verify API key exists
do {
    let key = try apiKeyProvider()
    print("✓ API Key gefunden (\(key.prefix(10))...)")
} catch {
    print("✗ Kein API Key in Keychain: \(error)")
    print("  Speichere mit: security add-generic-password -s \"com.derfluisterer\" -a \"anthropic-api-key\" -w \"sk-ant-...\" -U")
    exit(1)
}
print("")

let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: apiKeyProvider)

Task {
    // Test 1: Neutral mode
    print("Test 1: Neutral-Modus (Grammatik/Zeichensetzung)")
    let config1 = CorrectionConfig(contextMode: .neutral, timeoutMs: 5000)
    let corrector = TextCorrectorImpl(config: config1, transport: transport, apiKeyProvider: apiKeyProvider)

    let input1 = TranscriptionResult.final(FinalTranscription(
        text: "also ähm ich wollte mal fragen ob wir uns morgen treffen können weil ich hab da noch was wichtiges zu besprechen",
        segments: [],
        processingTime: .milliseconds(100)
    ))

    let result1 = await corrector.correct(input1)
    printResult("Neutral", result1)
    print("")

    // Test 2: Formal mode
    print("Test 2: Formell-Modus")
    corrector.updateConfig(CorrectionConfig(contextMode: .formal, timeoutMs: 5000))

    let input2 = TranscriptionResult.final(FinalTranscription(
        text: "hey kannst du mir mal die daten schicken die brauch ich bis morgen",
        segments: [],
        processingTime: .milliseconds(100)
    ))

    let result2 = await corrector.correct(input2)
    printResult("Formal", result2)
    print("")

    // Test 3: With personal dictionary
    print("Test 3: Mit persönlichem Wörterbuch")
    corrector.updateConfig(CorrectionConfig(
        contextMode: .neutral,
        personalDictionary: ["SwiftUI", "WhisperKit", "DerFlüsterer"],
        timeoutMs: 5000
    ))

    let input3 = TranscriptionResult.final(FinalTranscription(
        text: "ich arbeite gerade an der flüsterer app die nutzt whisper kit und swift ui für die oberfläche",
        segments: [],
        processingTime: .milliseconds(100)
    ))

    let result3 = await corrector.correct(input3)
    printResult("Dictionary", result3)
    print("")

    // Test 4: Debug Snapshot
    print("Test 4: Debug Snapshot")
    if let snapshot = corrector.lastDebugSnapshot {
        print("  System Prompt (Anfang): \(String(snapshot.request.prefix(100)))...")
        print("  Response: \(snapshot.response ?? "nil")")
        print("  Timestamp: \(snapshot.timestamp)")
    } else {
        print("  ✗ Kein Debug Snapshot vorhanden")
    }

    exit(0)
}

func printResult(_ label: String, _ outcome: CorrectionOutcome) {
    switch outcome {
    case .corrected(let text, let stats):
        print("  ✓ [\(label)] Korrigiert: \(text)")
        print("    Latenz: \(stats.latencyMs)ms, Retry: \(stats.wasRetry)")
    case .fallbackRaw(let text, let reason):
        print("  ✗ [\(label)] Fallback: \(text)")
        print("    Grund: \(reason)")
    }
}

RunLoop.main.run()
