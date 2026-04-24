import XCTest
@testable import DerFluisterer

final class MockCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
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
func makeSettingsManager(
    suiteName: String = "test.\(UUID())",
    credentialStore: MockCredentialStore = MockCredentialStore(),
    validator: MockAPIKeyValidator = noOpValidator
) -> SettingsManager {
    SettingsManager(
        defaults: UserDefaults(suiteName: suiteName)!,
        credentialStore: credentialStore,
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

    func test_defaultAppMappings_arePreConfigured() {
        let defaults = CorrectionSettings()
        XCTAssertEqual(defaults.appMapping["com.apple.mail"], .formal)
        XCTAssertEqual(defaults.appMapping["com.tinyspeck.slackmacgap"], .informal)
        XCTAssertEqual(defaults.appMapping["com.microsoft.Outlook"], .formal)
    }

    func test_correctionSettings_taskFlagsDefaultTrue() {
        let defaults = CorrectionSettings()
        XCTAssertTrue(defaults.taskGrammar)
        XCTAssertTrue(defaults.taskFillerRemoval)
        XCTAssertTrue(defaults.taskWrittenLanguage)
        XCTAssertTrue(defaults.taskPunctuation)
        XCTAssertTrue(defaults.taskPreventHallucination)
        XCTAssertTrue(defaults.isLLMEnabled)
    }

    func test_correctionSettings_isLLMEnabledFalseWhenAllTasksOff() {
        var settings = CorrectionSettings()
        settings.taskGrammar = false
        settings.taskFillerRemoval = false
        settings.taskWrittenLanguage = false
        settings.taskPunctuation = false
        settings.taskPreventHallucination = false
        XCTAssertFalse(settings.isLLMEnabled)
    }
}

// MARK: - Migration

@MainActor
final class SettingsManagerMigrationTests: XCTestCase {

    func test_correctionSettings_legacyJSONWithoutTaskFlags_decodesWithTrueDefaults() throws {
        // Simulates a JSON persisted before Issue #37 (no task* keys).
        let legacyJSON = """
        {
            "contextMode": "formal",
            "appMapping": {},
            "allowRephrasing": true,
            "allowShortening": false,
            "allowRestructuring": false,
            "personalDictionary": ["SwiftUI"],
            "llmTimeoutMs": 1500,
            "showAPIKeyNotification": false
        }
        """
        let data = legacyJSON.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CorrectionSettings.self, from: data)

        XCTAssertTrue(decoded.taskGrammar)
        XCTAssertTrue(decoded.taskFillerRemoval)
        XCTAssertTrue(decoded.taskWrittenLanguage)
        XCTAssertTrue(decoded.taskPunctuation)
        XCTAssertTrue(decoded.taskPreventHallucination)
        // Existing fields preserved
        XCTAssertEqual(decoded.contextMode, .formal)
        XCTAssertTrue(decoded.allowRephrasing)
        XCTAssertEqual(decoded.personalDictionary, ["SwiftUI"])
        XCTAssertEqual(decoded.llmTimeoutMs, 1500)
        XCTAssertFalse(decoded.showAPIKeyNotification)
    }

    func test_correctionSettings_emptyJSON_yieldsAllDefaults() throws {
        let emptyJSON = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CorrectionSettings.self, from: emptyJSON)
        XCTAssertEqual(decoded, CorrectionSettings())
    }

    func test_correctionSettings_roundTripPreservesTaskFlags() throws {
        var original = CorrectionSettings()
        original.taskGrammar = false
        original.taskPreventHallucination = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CorrectionSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

// MARK: - Persistence

@MainActor
final class SettingsManagerPersistenceTests: XCTestCase {

    func test_audioSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let credentialStore = MockCredentialStore()

        let first = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)
        first.audio.language = .en
        first.audio.soundsEnabled = false

        let second = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)

        XCTAssertEqual(second.audio.language, .en)
        XCTAssertEqual(second.audio.soundsEnabled, false)
    }

    func test_correctionSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let credentialStore = MockCredentialStore()

        let first = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)
        first.correction.contextMode = .formal
        first.correction.allowRephrasing = true
        first.correction.personalDictionary = ["WhisperKit", "SwiftUI"]
        first.correction.llmTimeoutMs = 1200

        let second = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)

        XCTAssertEqual(second.correction.contextMode, .formal)
        XCTAssertEqual(second.correction.allowRephrasing, true)
        XCTAssertEqual(second.correction.personalDictionary, ["WhisperKit", "SwiftUI"])
        XCTAssertEqual(second.correction.llmTimeoutMs, 1200)
    }

    func test_systemSettings_persistAcrossInstances() {
        let suiteName = "test.persist.\(UUID())"
        let credentialStore = MockCredentialStore()

        let first = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)
        first.system.historyLimit = 50
        first.system.debugMode = true

        let second = makeSettingsManager(suiteName: suiteName, credentialStore: credentialStore)

        XCTAssertEqual(second.system.historyLimit, 50)
        XCTAssertEqual(second.system.debugMode, true)
    }

    func test_systemSettings_dismissedUpdateVersion_defaultsToNil() {
        let settings = SystemSettings()
        XCTAssertNil(settings.dismissedUpdateVersion)
    }

    func test_systemSettings_dismissedUpdateVersion_persistsAcrossDecode() throws {
        let original = SystemSettings(autoStart: false, historyLimit: 100, debugMode: false, dismissedUpdateVersion: "0.2.0")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SystemSettings.self, from: data)
        XCTAssertEqual(decoded.dismissedUpdateVersion, "0.2.0")
    }
}

// MARK: - API Key

@MainActor
final class SettingsManagerAPIKeyTests: XCTestCase {

    private func makeSUT() -> (SettingsManager, MockCredentialStore) {
        let credentialStore = MockCredentialStore()
        let sut = makeSettingsManager(credentialStore: credentialStore)
        return (sut, credentialStore)
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
        let credentialStore = MockCredentialStore()
        let validator = MockAPIKeyValidator()
        let sut = makeSettingsManager(credentialStore: credentialStore, validator: validator)
        try sut.setAPIKey("sk-ant-valid-key")

        await sut.validateAPIKey()

        XCTAssertEqual(sut.apiKeyStatus, .valid)
    }

    func test_validateAPIKey_transitionsToInvalidOnError() async throws {
        let credentialStore = MockCredentialStore()
        let validator = MockAPIKeyValidator()
        validator.result = .failure(NSError(domain: "test", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid API key"]))
        let sut = makeSettingsManager(credentialStore: credentialStore, validator: validator)
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
