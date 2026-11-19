import XCTest
@testable import Kalizap

final class ClaudeAPITransportTests: XCTestCase {

    // MARK: - Mock

    private final class MockHTTPSession: HTTPDataSending, @unchecked Sendable {
        var capturedRequest: URLRequest? { requests.last }
        var requests: [URLRequest] = []
        var responseData: Data = Data()
        var responseStatusCode: Int = 200
        /// Status codes for successive calls; falls back to `responseStatusCode` when exhausted.
        var statusSequence: [Int] = []
        var error: (any Error)?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            if let error { throw error }
            let status = statusSequence.isEmpty ? responseStatusCode : statusSequence.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
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

        _ = try await transport("system", "user text", 800, .haiku)

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

        _ = try await transport("my system prompt", "hello world", 800, .haiku)

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "claude-haiku-5-5")
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

        let result = try await transport("system", "input", 800, .haiku)

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
            _ = try await transport("system", "input", 800, .haiku)
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
            _ = try await transport("system", "input", 800, .haiku)
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
            _ = try await transport("system", "input", 800, .haiku)
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
            _ = try await transport("system", "input", 800, .haiku)
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(error is ClaudeAPIError)
        }
    }

    // MARK: - Model selection & thinking (#57)

    private func body(of request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_transport_usesResolvedModelAndDisablesThinkingPerFamily() async throws {
        let session = MockHTTPSession()
        session.responseData = makeSuccessResponse(text: "ok")
        let transport = ClaudeAPITransport.makeTransport(
            apiKeyProvider: { "key" },
            modelID: { $0 == .haiku ? "claude-haiku-6" : "claude-sonnet-6" },
            session: session
        )

        _ = try await transport("s", "u", 800, .haiku)
        let haiku = try body(of: session.capturedRequest)
        XCTAssertEqual(haiku["model"] as? String, "claude-haiku-6")
        XCTAssertEqual((haiku["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual((haiku["output_config"] as? [String: String])?["effort"], "low")

        _ = try await transport("s", "u", 800, .sonnet)
        let sonnet = try body(of: session.capturedRequest)
        XCTAssertEqual(sonnet["model"] as? String, "claude-sonnet-6")
        XCTAssertEqual((sonnet["thinking"] as? [String: String])?["type"], "between_tools")
    }

    func test_transport_returnsTextBlockEvenWhenThinkingBlockComesFirst() async throws {
        let session = MockHTTPSession()
        session.responseData = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": "Korrigiert"]]
        ])
        let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: { "key" }, session: session)

        let result = try await transport("s", "u", 800, .haiku)

        XCTAssertEqual(result, "Korrigiert")
    }

    func test_transport_retriesOnceWithMinimalRequestOn400() async throws {
        let session = MockHTTPSession()
        session.statusSequence = [400, 200]
        session.responseData = makeSuccessResponse(text: "ok")
        let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: { "key" }, session: session)

        let result = try await transport("sys", "u", 800, .haiku)

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(session.requests.count, 2)
        let retry = try body(of: session.requests[1])
        XCTAssertEqual(Set(retry.keys), ["model", "max_tokens", "system", "messages"])
        XCTAssertEqual(retry["model"] as? String, "claude-haiku-5-5")
    }

    func test_transport_throwsWhenMinimalRetryAlsoFails() async {
        let session = MockHTTPSession()
        session.responseStatusCode = 400
        session.responseData = Data("bad".utf8)
        let transport = ClaudeAPITransport.makeTransport(apiKeyProvider: { "key" }, session: session)

        do {
            _ = try await transport("s", "u", 800, .haiku)
            XCTFail("Expected error")
        } catch let error as ClaudeAPIError {
            XCTAssertEqual(error, .httpError(statusCode: 400, body: "bad"))
            XCTAssertEqual(session.requests.count, 2)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
