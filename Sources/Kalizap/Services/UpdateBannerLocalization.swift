import Foundation

public struct BannerStrings: Sendable {
    public let titleTemplate: String
    public let homebrewInstructionLabel: String
    public let directDownloadInstructionLabel: String
    public let quarantineHint: String
    public let copyButton: String
    public let openReleaseButton: String
    public let laterButton: String
    public let checkForUpdatesButton: String
}

public enum UpdateBannerLocalization {

    public enum Language: Sendable {
        case german
        case english

        public static func from(localeIdentifier: String?) -> Language {
            guard let id = localeIdentifier?.lowercased() else { return .german }
            return id.hasPrefix("en") ? .english : .german
        }
    }

    public static func strings(for language: Language) -> BannerStrings {
        switch language {
        case .german:
            return BannerStrings(
                titleTemplate: "Neue Version verfügbar: {version}",
                homebrewInstructionLabel: "Update via Homebrew:",
                directDownloadInstructionLabel: "Update herunterladen von GitHub Releases.",
                quarantineHint: "Hinweis: Nach Installation Quarantäne-Flag entfernen.",
                copyButton: "Kopieren",
                openReleaseButton: "Release-Seite öffnen",
                laterButton: "Später",
                checkForUpdatesButton: "Nach Updates suchen"
            )
        case .english:
            return BannerStrings(
                titleTemplate: "New version available: {version}",
                homebrewInstructionLabel: "Update via Homebrew:",
                directDownloadInstructionLabel: "Download update from GitHub Releases.",
                quarantineHint: "Note: Remove the quarantine flag after installing.",
                copyButton: "Copy",
                openReleaseButton: "Open release page",
                laterButton: "Later",
                checkForUpdatesButton: "Check for updates"
            )
        }
    }
}
