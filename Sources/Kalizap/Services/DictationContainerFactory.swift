import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.sandhofer.kalizap", category: "DictationStore")

/// Builds the SwiftData container for dictation history at an app-owned location.
///
/// The SwiftData default location (`~/Library/Application Support/default.store`) is shared
/// by every non-sandboxed process — e.g. macOS' `icloudmailagent` stores its own schema there,
/// which made Kalizap crash at launch (#54).
public enum DictationContainerFactory {

    public static func makeContainer(storeURL: URL) -> ModelContainer {
        do {
            return try openStore(at: storeURL)
        } catch {
            logger.error("Failed to open \(storeURL.path, privacy: .public): \(String(describing: error), privacy: .public) — moving store aside")
            moveAside(storeURL)
        }
        do {
            return try openStore(at: storeURL)
        } catch {
            logger.fault("Retry failed: \(String(describing: error), privacy: .public) — falling back to in-memory store, history not persisted")
            return makeInMemoryContainer()
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        // In-memory creation has no file-system dependency; failure here is a programming error.
        try! ModelContainer(
            for: DictationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func openStore(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return try ModelContainer(
            for: DictationRecord.self,
            migrationPlan: DictationMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    /// Renames the SQLite store and its sidecar files (`-wal`, `-shm`) to `<name>.broken-<timestamp>…`.
    private static func moveAside(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: "\(url.path).broken-\(stamp)\(suffix)")
            try? fm.moveItem(at: source, to: target)
        }
    }
}
