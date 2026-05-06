import Foundation

/// Pure-Swift visibility helper for SettingsView — testable without SwiftUI.
public enum SettingsVisibility {
    /// App-Zuordnung sichtbar nur wenn Auto-Modus gewählt UND LLM-Korrektur überhaupt aktiv.
    public static func showAppMapping(contextMode: ContextMode, isLLMEnabled: Bool) -> Bool {
        contextMode == .auto && isLLMEnabled
    }

    /// Debug-Sektionen (History-Limit, LLM-Timeout, API-Key-Notification) sichtbar
    /// nur wenn Debug-Modus aktiv.
    public static func showDebugSections(debugMode: Bool) -> Bool {
        debugMode
    }

    /// Stil- und Intensität-Controls sind aktiv nur wenn LLM-Korrektur läuft.
    public static func styleControlsEnabled(isLLMEnabled: Bool) -> Bool {
        isLLMEnabled
    }
}
