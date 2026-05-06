import XCTest
@testable import Kalizap

final class GitHubReleasesClientTests: XCTestCase {

    private final class FakeHTTPSender: HTTPDataSending, @unchecked Sendable {
        var dataToReturn: Data = Data()
        var responseToReturn: URLResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        var errorToThrow: Error?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            if let errorToThrow { throw errorToThrow }
            return (dataToReturn, responseToReturn)
        }
    }

    func test_fetchLatestReleaseTag_success_returnsTagName() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = try JSONSerialization.data(withJSONObject: ["tag_name": "v0.2.0"])
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertEqual(tag, "v0.2.0")
    }

    func test_fetchLatestReleaseTag_notFound404_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.responseToReturn = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_networkError_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.errorToThrow = URLError(.notConnectedToInternet)
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_malformedJson_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = Data("not valid json".utf8)
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_missingTagNameField_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = try JSONSerialization.data(withJSONObject: ["other_field": "value"])
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }
}
