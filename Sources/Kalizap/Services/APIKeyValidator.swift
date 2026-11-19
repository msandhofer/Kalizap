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
        // Listing models needs a valid key but no model ID and costs no tokens.
        var request = URLRequest(url: AnthropicDefaults.modelsURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: AnthropicDefaults.Headers.apiKey)
        request.setValue(AnthropicDefaults.apiVersion, forHTTPHeaderField: AnthropicDefaults.Headers.version)

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
