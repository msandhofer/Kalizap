import AppKit

public final class NSPasteboardClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let pasteboard = NSPasteboard.general

    public init() {}

    public func backup() async throws -> ClipboardSnapshot {
        let data = pasteboard.data(forType: .string)
        return ClipboardSnapshot(data: data)
    }

    public func set(text: String) async throws {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func restore(from snapshot: ClipboardSnapshot) async throws {
        pasteboard.clearContents()
        if let data = snapshot.data {
            pasteboard.setData(data, forType: .string)
        }
    }
}
