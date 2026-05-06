import XCTest
@testable import Kalizap

final class MockLaunchAtLoginService: LaunchAtLoginProtocol, @unchecked Sendable {
    var isEnabled: Bool = false
    var registerCallCount = 0
    var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        isEnabled = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        isEnabled = false
    }
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {

    func test_enableAutoStart_registersService() throws {
        let mock = MockLaunchAtLoginService()
        let credentialStore = MockCredentialStore()
        let validator = MockAPIKeyValidator()
        let sut = SettingsManager(
            defaults: UserDefaults(suiteName: "test.autostart.\(UUID())")!,
            credentialStore: credentialStore,
            apiKeyValidator: validator,
            launchAtLogin: mock
        )

        try sut.setAutoStart(true)

        XCTAssertEqual(mock.registerCallCount, 1)
        XCTAssertTrue(sut.system.autoStart)
    }

    func test_disableAutoStart_unregistersService() throws {
        let mock = MockLaunchAtLoginService()
        let credentialStore = MockCredentialStore()
        let validator = MockAPIKeyValidator()
        let sut = SettingsManager(
            defaults: UserDefaults(suiteName: "test.autostart.\(UUID())")!,
            credentialStore: credentialStore,
            apiKeyValidator: validator,
            launchAtLogin: mock
        )

        try sut.setAutoStart(true)
        try sut.setAutoStart(false)

        XCTAssertEqual(mock.unregisterCallCount, 1)
        XCTAssertFalse(sut.system.autoStart)
    }
}
