import XCTest
@testable import DerFluisterer

final class ClaudeAPITransportTests: XCTestCase {

    // MARK: - Mock

    private final class MockHTTPSession: HTTPDataSending, @unchecked Sendable {
        var capturedRequest: URLRequest?
        var responseData: Data = Data()
        var responseStatusCode: Int = 200
        var error: (any Error)?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            capturedRequest = request
            if let error { throw error }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: responseStatusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (responseData, response)
        }
    }

    private func makeSuccessResponse(text: String) -> Data {
        let json: [String: Any] = [
            "content": [["type": "text", "text": text]],
            "model": "claude-haiku-4-5-20251001",
            "role": "assistant"
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Request construction

    func test_transport_setsCorrectHeaders() async throws {
        let session = MockHTTPSession()
        session.responseData = makeSuccessResponse(text: "ok")
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "sk-test-key" },
            session: session
        )

        _ = try await transport("system", "user text", 800)

        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.url, AnthropicDefaults.apiURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), AnthropicDefaults.Headers.contentType)
        XCTAssertEqual(request.value(forHTTPHeaderField: AnthropicDefaults.Headers.apiKey), "sk-test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: AnthropicDefaults.Headers.version), AnthropicDefaults.apiVersion)
    }

    func test_transport_sendsCorrectBody() async throws {
        let session = MockHTTPSession()
        session.responseData = makeSuccessResponse(text: "ok")
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "sk-test-key" },
            session: session
        )

        _ = try await transport("my system prompt", "hello world", 800)

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, AnthropicDefaults.model)
        XCTAssertEqual(json["max_tokens"] as? Int, AnthropicDefaults.maxTokens)
        XCTAssertEqual(json["system"] as? String, "my system prompt")

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "hello world")
    }

    // MARK: - Response parsing

    func test_transport_parsesSuccessfulResponse() async throws {
        let session = MockHTTPSession()
        session.responseData = makeSuccessResponse(text: "Korrigierter Text")
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            session: session
        )

        let result = try await transport("system", "input", 800)

        XCTAssertEqual(result, "Korrigierter Text")
    }

    // MARK: - Error handling

    func test_transport_throwsOnNon200Status() async {
        let session = MockHTTPSession()
        session.responseStatusCode = 429
        session.responseData = Data("{\"error\":\"rate limited\"}".utf8)
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            session: session
        )

        do {
            _ = try await transport("system", "input", 800)
            XCTFail("Expected error")
        } catch let error as ClaudeAPIError {
            XCTAssertEqual(error, .httpError(statusCode: 429, body: "{\"error\":\"rate limited\"}"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_transport_throwsOnMalformedJSON() async {
        let session = MockHTTPSession()
        session.responseData = Data("not json".utf8)
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            session: session
        )

        do {
            _ = try await transport("system", "input", 800)
            XCTFail("Expected error")
        } catch {
            // JSONSerialization throws CocoaError before we reach parseError — correct behavior
        }
    }

    func test_transport_throwsParseErrorOnMissingContent() async {
        let session = MockHTTPSession()
        session.responseData = Data("{\"model\":\"test\"}".utf8)
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            session: session
        )

        do {
            _ = try await transport("system", "input", 800)
            XCTFail("Expected error")
        } catch let error as ClaudeAPIError {
            XCTAssertEqual(error, .parseError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_transport_propagatesNetworkError() async {
        let session = MockHTTPSession()
        session.error = NSError(domain: NSURLErrorDomain, code: -1009)
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            session: session
        )

        do {
            _ = try await transport("system", "input", 800)
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(error is ClaudeAPIError)
        }
    }
}
