import XCTest
@testable import DerFluisterer

final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    var storage: [String: String] = [:]

    func store(_ value: String, for account: String) throws {
        storage[account] = value
    }

    func retrieve(for account: String) throws -> String {
        guard let value = storage[account] else {
            throw KeychainError.itemNotFound
        }
        return value
    }

    func delete(for account: String) throws {
        storage.removeValue(forKey: account)
    }
}

enum KeychainError: Error {
    case itemNotFound
}

final class MockAPIKeyValidator: APIKeyValidating, @unchecked Sendable {
    var result: Result<Void, Error> = .success(())

    func validate(apiKey: String) async throws {
        try result.get()
    }
}

private let noOpValidator = MockAPIKeyValidator()

@MainActor
private func makeSettingsManager(
    suiteName: String = "test.\(UUID())",
    keychain: MockKeychainService = MockKeychainService(),
    validator: MockAPIKeyValidator = noOpValidator
) -> SettingsManager {
    SettingsManager(
        defaults: UserDefaults(suiteName: suiteName)!,
        keychain: keychain,
        apiKeyValidator: validator
    )
}

// MARK: - Defaults

@MainActor
final class SettingsManagerDefaultsTests: XCTestCase {

    func test_newSettingsManager_hasCorrectAudioDefaults() {
        let sut = makeSettingsManager()
        XCTAssertEqual(sut.audio, AudioSettings())
    }

    func test_newSettingsManager_hasCorrectHotkeyDefaults() {
        let sut = makeSettingsManager()
        XCTAssertEqual(sut.hotkey, HotkeySettings())
    }

    func test_newSettingsManager_hasCorrectCorrectionDefaults() {
        let sut = makeSettingsManager()
        XCTAssertEqual(sut.correction, CorrectionSettings())
    }

    func test_newSettingsManager_hasCorrectSystemDefaults() {
        let sut = makeSettingsManager()
        XCTAssertEqual(sut.system, SystemSettings())
    }
}

// MARK: - Persistence

@MainActor
final class SettingsManagerPersistenceTests: XCTestCase {

    func test_audioSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let keychain = MockKeychainService()

        let first = makeSettingsManager(suiteName: suiteName, keychain: keychain)
        first.audio.language = .en
        first.audio.soundsEnabled = false

        let second = makeSettingsManager(suiteName: suiteName, keychain: keychain)

        XCTAssertEqual(second.audio.language, .en)
        XCTAssertEqual(second.audio.soundsEnabled, false)
    }

    func test_correctionSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let keychain = MockKeychainService()

        let first = makeSettingsManager(suiteName: suiteName, keychain: keychain)
        first.correction.contextMode = .formal
        first.correction.allowRephrasing = true
        first.correction.personalDictionary = ["WhisperKit", "SwiftUI"]
        first.correction.llmTimeoutMs = 1200

        let second = makeSettingsManager(suiteName: suiteName, keychain: keychain)

        XCTAssertEqual(second.correction.contextMode, .formal)
        XCTAssertEqual(second.correction.allowRephrasing, true)
        XCTAssertEqual(second.correction.personalDictionary, ["WhisperKit", "SwiftUI"])
        XCTAssertEqual(second.correction.llmTimeoutMs, 1200)
    }

    func test_systemSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let keychain = MockKeychainService()

        let first = makeSettingsManager(suiteName: suiteName, keychain: keychain)
        first.system.historyLimit = 50
        first.system.debugMode = true

        let second = makeSettingsManager(suiteName: suiteName, keychain: keychain)

        XCTAssertEqual(second.system.historyLimit, 50)
        XCTAssertEqual(second.system.debugMode, true)
    }
}

// MARK: - API Key

@MainActor
final class SettingsManagerAPIKeyTests: XCTestCase {

    private func makeSUT() -> (SettingsManager, MockKeychainService) {
        let keychain = MockKeychainService()
        let sut = makeSettingsManager(keychain: keychain)
        return (sut, keychain)
    }

    func test_setAPIKey_storesInKeychain() throws {
        let (sut, keychain) = makeSUT()

        try sut.setAPIKey("sk-ant-test-key-123")

        XCTAssertEqual(keychain.storage["anthropic-api-key"], "sk-ant-test-key-123")
    }

    func test_resolveAPIKey_retrievesStoredKey() throws {
        let (sut, _) = makeSUT()

        try sut.setAPIKey("sk-ant-test-key-123")
        let key = try sut.resolveAPIKey()

        XCTAssertEqual(key, "sk-ant-test-key-123")
    }

    func test_resolveAPIKey_throwsWhenNoKeyStored() {
        let (sut, _) = makeSUT()

        XCTAssertThrowsError(try sut.resolveAPIKey())
    }

    func test_deleteAPIKey_removesFromKeychain() throws {
        let (sut, keychain) = makeSUT()

        try sut.setAPIKey("sk-ant-test-key-123")
        try sut.deleteAPIKey()

        XCTAssertNil(keychain.storage["anthropic-api-key"])
    }

    func test_deleteAPIKey_setsStatusToMissing() throws {
        let (sut, _) = makeSUT()

        try sut.setAPIKey("sk-ant-test-key-123")
        try sut.deleteAPIKey()

        XCTAssertEqual(sut.apiKeyStatus, .missing)
    }

    func test_newSettingsManager_withoutKey_statusIsMissing() {
        let (sut, _) = makeSUT()

        XCTAssertEqual(sut.apiKeyStatus, .missing)
    }
}

// MARK: - Validation

@MainActor
final class SettingsManagerValidationTests: XCTestCase {

    func test_validateAPIKey_transitionsToValid() async throws {
        let keychain = MockKeychainService()
        let validator = MockAPIKeyValidator()
        let sut = makeSettingsManager(keychain: keychain, validator: validator)
        try sut.setAPIKey("sk-ant-valid-key")

        await sut.validateAPIKey()

        XCTAssertEqual(sut.apiKeyStatus, .valid)
    }

    func test_validateAPIKey_transitionsToInvalidOnError() async throws {
        let keychain = MockKeychainService()
        let validator = MockAPIKeyValidator()
        validator.result = .failure(NSError(domain: "test", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid API key"]))
        let sut = makeSettingsManager(keychain: keychain, validator: validator)
        try sut.setAPIKey("sk-ant-bad-key")

        await sut.validateAPIKey()

        XCTAssertEqual(sut.apiKeyStatus, .invalid("Invalid API key"))
    }

    func test_validateAPIKey_staysMissingWhenNoKey() async {
        let validator = MockAPIKeyValidator()
        let sut = makeSettingsManager(validator: validator)

        await sut.validateAPIKey()

        XCTAssertEqual(sut.apiKeyStatus, .missing)
    }
}
