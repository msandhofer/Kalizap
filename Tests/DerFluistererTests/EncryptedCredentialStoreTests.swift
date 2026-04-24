import XCTest
@testable import DerFluisterer

final class EncryptedCredentialStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ecs-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func makeSUT(
        identity: any HardwareIdentityProviding = FakeIdentity(deviceID: "test-device", userName: "test-user"),
        appSecret: Data = Data(repeating: 0xAB, count: 32)
    ) -> EncryptedCredentialStore {
        EncryptedCredentialStore(
            baseDirectory: tempDir,
            identity: identity,
            appSecret: appSecret
        )
    }

    func test_storeAndRetrieve_roundTripInSameInstance() throws {
        let sut = makeSUT()

        try sut.store("sk-ant-test-123", for: "anthropic-api-key")
        let retrieved = try sut.retrieve(for: "anthropic-api-key")

        XCTAssertEqual(retrieved, "sk-ant-test-123")
    }

    func test_storeAndRetrieve_persistsAcrossInstances() throws {
        let identity = FakeIdentity(deviceID: "persist-device", userName: "persist-user")
        let secret = Data(repeating: 0xCD, count: 32)

        let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secret)
        try writer.store("sk-ant-persist-456", for: "anthropic-api-key")

        let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secret)
        let retrieved = try reader.retrieve(for: "anthropic-api-key")

        XCTAssertEqual(retrieved, "sk-ant-persist-456")
    }

    func test_retrieve_failsWhenDeviceIdentifierDiffers() throws {
        let secret = Data(repeating: 0xEE, count: 32)
        let writerIdentity = FakeIdentity(deviceID: "device-A", userName: "user-X")
        let readerIdentity = FakeIdentity(deviceID: "device-B", userName: "user-X")

        let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: writerIdentity, appSecret: secret)
        try writer.store("sk-ant-device-bound", for: "anthropic-api-key")

        let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: readerIdentity, appSecret: secret)

        XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
            guard case EncryptedCredentialStoreError.decryptionFailed = error else {
                XCTFail("Expected decryptionFailed, got \(error)")
                return
            }
        }
    }

    func test_retrieve_failsWhenUserNameDiffers() throws {
        let secret = Data(repeating: 0xFF, count: 32)
        let writerIdentity = FakeIdentity(deviceID: "device-same", userName: "alice")
        let readerIdentity = FakeIdentity(deviceID: "device-same", userName: "bob")

        let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: writerIdentity, appSecret: secret)
        try writer.store("sk-ant-user-bound", for: "anthropic-api-key")

        let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: readerIdentity, appSecret: secret)

        XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
            guard case EncryptedCredentialStoreError.decryptionFailed = error else {
                XCTFail("Expected decryptionFailed, got \(error)")
                return
            }
        }
    }

    func test_retrieve_failsWhenAppSecretDiffers() throws {
        let identity = FakeIdentity(deviceID: "same-device", userName: "same-user")
        let secretA = Data(repeating: 0x11, count: 32)
        let secretB = Data(repeating: 0x22, count: 32)

        let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secretA)
        try writer.store("sk-ant-secret-bound", for: "anthropic-api-key")

        let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secretB)

        XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
            guard case EncryptedCredentialStoreError.decryptionFailed = error else {
                XCTFail("Expected decryptionFailed, got \(error)")
                return
            }
        }
    }

    func test_retrieve_throwsItemNotFoundWhenNoFile() {
        let sut = makeSUT()

        XCTAssertThrowsError(try sut.retrieve(for: "nonexistent-account")) { error in
            guard case EncryptedCredentialStoreError.itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)")
                return
            }
        }
    }

    func test_store_overwritesExistingValue() throws {
        let sut = makeSUT()

        try sut.store("old-key", for: "anthropic-api-key")
        try sut.store("new-key", for: "anthropic-api-key")

        let retrieved = try sut.retrieve(for: "anthropic-api-key")
        XCTAssertEqual(retrieved, "new-key")
    }

    func test_delete_removesStoredValue() throws {
        let sut = makeSUT()

        try sut.store("will-be-deleted", for: "anthropic-api-key")
        try sut.delete(for: "anthropic-api-key")

        XCTAssertThrowsError(try sut.retrieve(for: "anthropic-api-key")) { error in
            guard case EncryptedCredentialStoreError.itemNotFound = error else {
                XCTFail("Expected itemNotFound, got \(error)")
                return
            }
        }
    }

    func test_delete_isNoOpWhenFileMissing() throws {
        let sut = makeSUT()
        XCTAssertNoThrow(try sut.delete(for: "nonexistent"))
    }
}

private struct FakeIdentity: HardwareIdentityProviding {
    let deviceID: String
    let userNameValue: String

    init(deviceID: String, userName: String) {
        self.deviceID = deviceID
        self.userNameValue = userName
    }

    func deviceIdentifier() throws -> String { deviceID }
    func userName() -> String { userNameValue }
}
