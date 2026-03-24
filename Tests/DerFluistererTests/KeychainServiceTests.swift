import XCTest
@testable import DerFluisterer

final class KeychainServiceTests: XCTestCase {

    private let testService = "com.derfluisterer.test.\(UUID())"

    private func makeSUT() -> KeychainService {
        KeychainService(service: testService)
    }

    override func tearDown() {
        let sut = makeSUT()
        try? sut.delete(for: "test-account")
        super.tearDown()
    }

    func test_storeAndRetrieve_roundTrip() throws {
        let sut = makeSUT()

        try sut.store("my-secret-key", for: "test-account")
        let retrieved = try sut.retrieve(for: "test-account")

        XCTAssertEqual(retrieved, "my-secret-key")
    }

    func test_retrieve_throwsWhenNotFound() {
        let sut = makeSUT()

        XCTAssertThrowsError(try sut.retrieve(for: "nonexistent-account"))
    }

    func test_delete_removesStoredValue() throws {
        let sut = makeSUT()

        try sut.store("my-secret-key", for: "test-account")
        try sut.delete(for: "test-account")

        XCTAssertThrowsError(try sut.retrieve(for: "test-account"))
    }

    func test_store_overwritesExistingValue() throws {
        let sut = makeSUT()

        try sut.store("old-key", for: "test-account")
        try sut.store("new-key", for: "test-account")
        let retrieved = try sut.retrieve(for: "test-account")

        XCTAssertEqual(retrieved, "new-key")
    }
}
