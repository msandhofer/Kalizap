import Foundation
import os

public protocol ReleasesFetching: Sendable {
    func fetchLatestReleaseTag() async throws -> String?
}

public protocol HomebrewDetecting: Sendable {
    func detect() -> HomebrewStatus
}

extension GitHubReleasesClient: ReleasesFetching {}
extension HomebrewDetector: HomebrewDetecting {}

public final class UpdateChecker: @unchecked Sendable {
    private let currentVersion: SemanticVersion?
    private let releasesClient: any ReleasesFetching
    private let homebrewDetector: any HomebrewDetecting
    private let githubReleaseBaseURL: URL
    private let homebrewCaskCommand: String
    private let stateLock = OSAllocatedUnfairLock<UpdateState>(initialState: .unknown)

    public var lastCheckState: UpdateState {
        stateLock.withLock { $0 }
    }

    public init(
        currentVersion: String,
        releasesClient: any ReleasesFetching,
        homebrewDetector: any HomebrewDetecting,
        githubReleaseBaseURL: URL,
        homebrewCaskCommand: String
    ) {
        self.currentVersion = SemanticVersion(currentVersion)
        self.releasesClient = releasesClient
        self.homebrewDetector = homebrewDetector
        self.githubReleaseBaseURL = githubReleaseBaseURL
        self.homebrewCaskCommand = homebrewCaskCommand
    }

    public func checkNow() async -> UpdateState {
        let state = await computeState()
        stateLock.withLock { $0 = state }
        return state
    }

    /// Gibt true zurueck, wenn gecheckt wurde; false, wenn geskippt (letzter Check < 24h her).
    public func checkIfDue(defaults: UserDefaults) async -> Bool {
        let key = "updateChecker.lastCheckTimestamp"
        let now = Date()
        if let last = defaults.object(forKey: key) as? Date,
           now.timeIntervalSince(last) < 24 * 3600 {
            return false
        }
        _ = await checkNow()
        defaults.set(now, forKey: key)
        return true
    }

    private func computeState() async -> UpdateState {
        guard let current = currentVersion else { return .unknown }
        let tag: String?
        do {
            tag = try await releasesClient.fetchLatestReleaseTag()
        } catch {
            return .unknown
        }
        guard let tag, let latest = SemanticVersion(tag) else {
            return .unknown
        }
        if latest <= current { return .noUpdate }

        let versionString = "\(latest.major).\(latest.minor).\(latest.patch)"
        let method: UpdateMethod
        switch homebrewDetector.detect() {
        case .installedViaCask:
            method = .homebrewCask(command: homebrewCaskCommand)
        case .installedDirectDownload, .notInstalled:
            method = .directDownload(url: githubReleaseBaseURL)
        }
        return .available(version: versionString, method: method)
    }
}
