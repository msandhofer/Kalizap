import XCTest
@testable import Kalizap

final class MockURLSession: HTTPDataSending, @unchecked Sendable {
    var responseData: Data = Data()
    var responseStatus: Int = 200
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseStatus,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

final class APIKeyValidatorTests: XCTestCase {

    func test_validate_succeedsOn200() async throws {
        let session = MockURLSession()
        session.responseStatus = 200
        let sut = AnthropicAPIKeyValidator(session: session)

        try await sut.validate(apiKey: "sk-ant-valid")
        // No throw = success
    }

    func test_validate_throwsOn401() async {
        let session = MockURLSession()
        session.responseStatus = 401
        let sut = AnthropicAPIKeyValidator(session: session)

        do {
            try await sut.validate(apiKey: "sk-ant-invalid")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"), "Error should mention 401, got: \(error.localizedDescription)")
        }
    }

    func test_validate_throwsOnNetworkError() async {
        let session = MockURLSession()
        session.error = URLError(.notConnectedToInternet)
        let sut = AnthropicAPIKeyValidator(session: session)

        do {
            try await sut.validate(apiKey: "sk-ant-any")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
