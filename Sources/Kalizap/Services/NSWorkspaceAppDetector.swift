import AppKit

public final class NSWorkspaceAppDetector: ActiveAppDetecting, @unchecked Sendable {

    public init() {}

    public func frontmostApp() -> ActiveApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return ActiveApp(
            bundleIdentifier: app.bundleIdentifier ?? "unknown",
            localizedName: app.localizedName ?? "Unknown"
        )
    }

    /// Resolve a bundle identifier to a human-readable app name.
    public static func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    /// Resolve a bundle identifier to the app's icon, if installed.
    public static func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// List currently running regular apps (those with a dock icon).
    public static func runningApps(excluding bundleIDs: Set<String> = []) -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let bundleID = app.bundleIdentifier,
                      !bundleIDs.contains(bundleID) else { return nil }
                return (bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
