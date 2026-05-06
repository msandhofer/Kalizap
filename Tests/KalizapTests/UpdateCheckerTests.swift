import XCTest
@testable import Kalizap

final class UpdateCheckerTests: XCTestCase {

    private final class FakeReleasesClient: ReleasesFetching, @unchecked Sendable {
        var nextTag: String?
        func fetchLatestReleaseTag() async throws -> String? {
            nextTag
        }
    }

    private final class FakeHomebrewDetector: HomebrewDetecting, @unchecked Sendable {
        var status: HomebrewStatus = .notInstalled
        func detect() -> HomebrewStatus { status }
    }

    private func makeSUT(
        currentVersion: String = "0.1.0",
        releasesNext: String? = nil,
        homebrewStatus: HomebrewStatus = .notInstalled
    ) -> (UpdateChecker, FakeReleasesClient, FakeHomebrewDetector) {
        let releases = FakeReleasesClient()
        releases.nextTag = releasesNext
        let brew = FakeHomebrewDetector()
        brew.status = homebrewStatus
        let checker = UpdateChecker(
            currentVersion: currentVersion,
            releasesClient: releases,
            homebrewDetector: brew,
            githubReleaseBaseURL: URL(string: "https://github.com/msandhofer/Kalizap/releases/latest")!,
            homebrewCaskCommand: "brew upgrade --cask msandhofer/kalizap/kalizap"
        )
        return (checker, releases, brew)
    }

    func test_checkNow_noNewerVersion_returnsNoUpdate() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.2.0", releasesNext: "v0.2.0")
        let state = await sut.checkNow()
        XCTAssertEqual(state, .noUpdate)
    }

    func test_checkNow_olderInstalled_returnsAvailable() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .notInstalled)
        let state = await sut.checkNow()
        if case .available(let v, let method) = state {
            XCTAssertEqual(v, "0.2.0")
            if case .directDownload(let url) = method {
                XCTAssertEqual(url.absoluteString, "https://github.com/msandhofer/Kalizap/releases/latest")
            } else {
                XCTFail("Expected directDownload method")
            }
        } else {
            XCTFail("Expected .available")
        }
    }

    func test_checkNow_olderInstalled_viaCask_returnsHomebrewMethod() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .installedViaCask)
        let state = await sut.checkNow()
        if case .available(_, .homebrewCask(let command)) = state {
            XCTAssertTrue(command.contains("brew upgrade"))
        } else {
            XCTFail("Expected .available with homebrewCask")
        }
    }

    func test_checkNow_brewInstalledButNotViaCask_returnsDirectDownload() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .installedDirectDownload)
        let state = await sut.checkNow()
        if case .available(_, .directDownload) = state {
            // OK
        } else {
            XCTFail("Expected .available with directDownload")
        }
    }

    func test_checkNow_apiReturnsNil_returnsUnknown() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: nil)
        let state = await sut.checkNow()
        XCTAssertEqual(state, .unknown)
    }

    func test_checkNow_malformedTagName_returnsUnknown() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "not-a-version")
        let state = await sut.checkNow()
        XCTAssertEqual(state, .unknown)
    }

    // MARK: - Throttle (einmal pro 24h)

    func test_checkIfDue_firstCall_runs() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!

        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertTrue(didRun, "Erster Call muss laufen")
    }

    func test_checkIfDue_secondCallWithin24h_skips() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!

        _ = await sut.checkIfDue(defaults: defaults)
        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertFalse(didRun, "Zweiter Call innerhalb 24h muss skippen")
    }

    func test_checkIfDue_secondCallAfter24h_runs() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!

        let past = Date().addingTimeInterval(-25 * 3600)
        defaults.set(past, forKey: "updateChecker.lastCheckTimestamp")

        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertTrue(didRun, "Nach 24h muss erneut gecheckt werden")
    }
}
