import XCTest
@testable import DerFluisterer

// MARK: - UpdateSettings

final class UpdateSettingsTests: XCTestCase {

    func test_feedUnreachableWarning_nilWhenNeverChecked() {
        let sut = UpdateSettings()
        XCTAssertNil(sut.feedUnreachableWarning)
    }

    func test_feedUnreachableWarning_nilWhenRecentlyChecked() {
        let sut = UpdateSettings(lastSuccessfulUpdateCheck: Date())
        XCTAssertNil(sut.feedUnreachableWarning)
    }

    func test_feedUnreachableWarning_showsAfter30Days() {
        let sut = UpdateSettings(lastSuccessfulUpdateCheck: Date(timeIntervalSinceNow: -31 * 24 * 3600))
        XCTAssertNotNil(sut.feedUnreachableWarning)
    }
}

// MARK: - SettingsManager delegates feedUnreachableWarning

@MainActor
final class UpdateSettingsIntegrationTests: XCTestCase {

    func test_settingsManager_delegatesFeedWarningToUpdateSettings() {
        let sut = makeSettingsManager()
        sut.update.lastSuccessfulUpdateCheck = Date(timeIntervalSinceNow: -31 * 24 * 3600)
        XCTAssertEqual(sut.feedUnreachableWarning, sut.update.feedUnreachableWarning)
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
