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
}
