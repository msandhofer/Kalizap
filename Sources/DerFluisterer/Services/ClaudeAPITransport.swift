import Foundation

public enum ClaudeAPITransport {

    public static func makeTransport(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        session: any HTTPDataSending = URLSession.shared
    ) -> @Sendable (String, String, Int) async throws -> String {
        return { systemPrompt, userText, timeoutMs in
            let apiKey = try apiKeyProvider()

            var request = URLRequest(url: AnthropicDefaults.apiURL)
            request.httpMethod = "POST"
            request.setValue(AnthropicDefaults.Headers.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: AnthropicDefaults.Headers.apiKey)
            request.setValue(AnthropicDefaults.apiVersion, forHTTPHeaderField: AnthropicDefaults.Headers.version)

            let body: [String: Any] = [
                "model": AnthropicDefaults.model,
                "max_tokens": AnthropicDefaults.maxTokens,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": userText]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let content = json?["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let text = firstBlock["text"] as? String else {
                throw ClaudeAPIError.parseError
            }

            return text
        }
    }
}

public enum ClaudeAPIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case parseError

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .httpError(let code, let body):
            return "Claude API error \(code): \(body)"
        case .parseError:
            return "Failed to parse Claude API response"
        }
    }
}
