import Foundation
import Speech

// MARK: - Timing Helpers

func formatMs(_ duration: Duration) -> String {
    let total = duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
    return "\(total)ms"
}

func durationToMs(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1000
        + duration.components.attoseconds / 1_000_000_000_000_000
}

func printTimingTable(_ entries: [(String, String)]) {
    let maxLabel = entries.map(\.0.count).max() ?? 0
    print("")
    print("=== Timing ===")
    for (label, value) in entries {
        let padded = label.padding(toLength: maxLabel + 2, withPad: " ", startingAt: 0)
        print("  \(padded)\(value)")
    }
    print("")
}

// MARK: - Locale Resolution

func resolveLocale(_ arg: String) -> Locale {
    switch arg {
    case "de": return Locale(identifier: "de_DE")
    case "en": return Locale(identifier: "en_US")
    default:   return Locale(identifier: arg)
    }
}

// MARK: - SpeechAnalyzer Setup

@available(macOS 26, *)
func ensureLocaleInstalled(locale: Locale, transcriber: SpeechTranscriber) async throws {
    let installed = await SpeechTranscriber.installedLocales
    if !installed.contains(locale) {
        print("Lade Sprachmodell fuer \(locale.identifier)...")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        print("Sprachmodell installiert.")
    }
}

@available(macOS 26, *)
func createTranscriber(locale: Locale, preset: SpeechTranscriber.Preset) -> SpeechTranscriber {
    SpeechTranscriber(locale: locale, preset: preset)
}
