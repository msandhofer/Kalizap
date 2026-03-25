import XCTest
@testable import DerFluisterer

@MainActor
final class UpdateCheckerTests: XCTestCase {

    func test_feedUnreachableWarning_nilWhenNeverChecked() {
        let sut = makeSettingsManager()
        XCTAssertNil(sut.update.lastSuccessfulUpdateCheck)
        XCTAssertNil(sut.feedUnreachableWarning)
    }

    func test_feedUnreachableWarning_nilWhenRecentlyChecked() {
        let sut = makeSettingsManager()
        sut.update.lastSuccessfulUpdateCheck = Date()
        XCTAssertNil(sut.feedUnreachableWarning)
    }

    func test_feedUnreachableWarning_showsAfter30Days() {
        let sut = makeSettingsManager()
        sut.update.lastSuccessfulUpdateCheck = Date(timeIntervalSinceNow: -31 * 24 * 3600)
        XCTAssertNotNil(sut.feedUnreachableWarning)
    }
}

// MARK: - UpdateChecking Protocol

@MainActor
final class UpdateCheckingProtocolTests: XCTestCase {

    func test_checkForUpdates_callsThroughToUpdater() {
        let mock = MockUpdateChecker()
        mock.checkForUpdates()
        XCTAssertEqual(mock.checkForUpdatesCallCount, 1)
    }

    func test_canCheckForUpdates_defaultsToTrue() {
        let mock = MockUpdateChecker()
        XCTAssertTrue(mock.canCheckForUpdates)
    }
}

final class MockUpdateChecker: UpdateChecking, @unchecked Sendable {
    var canCheckForUpdates: Bool = true
    var checkForUpdatesCallCount = 0

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
    }
}

// Uses shared makeSettingsManager() from SettingsManagerTests.swift
