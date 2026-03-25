import Foundation
import Sparkle

@MainActor
public final class SparkleUpdater: UpdateChecking {
    private let updaterController: SPUStandardUpdaterController
    private let settings: SettingsManager
    public static let feedURL = URL(string: "https://github.com/msandhofer/Fluesterclon/releases/latest/download/appcast.xml")!
    public static let releaseNotesURL = URL(string: "https://github.com/msandhofer/Fluesterclon/releases")!

    private let delegateAdapter: SparkleDelegateAdapter

    public var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    public init(settings: SettingsManager) {
        self.settings = settings
        let adapter = SparkleDelegateAdapter()
        self.delegateAdapter = adapter
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: adapter,
            userDriverDelegate: nil
        )
        adapter.settings = settings
        configure()
    }

    public func start() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func configure() {
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = settings.update.autoCheckEnabled
        updater.automaticallyDownloadsUpdates = settings.update.silentAutoUpdate
    }
}

final class SparkleDelegateAdapter: NSObject, SPUUpdaterDelegate {
    weak var settings: SettingsManager?

    func feedURLString(for updater: SPUUpdater) -> String? {
        SparkleUpdater.feedURL.absoluteString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if error == nil {
            Task { @MainActor [weak settings] in
                settings?.update.lastSuccessfulUpdateCheck = Date()
            }
        }
    }
}
