import Foundation

public protocol HTTPDataSending: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataSending {}

public struct AnthropicAPIKeyValidator: APIKeyValidating {
    private let session: any HTTPDataSending

    public init(session: any HTTPDataSending = URLSession.shared) {
        self.session = session
    }

    public func validate(apiKey: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Data("""
        {"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}
        """.utf8)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyValidationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIKeyValidationError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

public enum APIKeyValidationError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let statusCode):
            return "API returned HTTP \(statusCode)"
        }
    }
}
