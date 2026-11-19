import Foundation

public enum ClaudeAPITransport {

    /// - Parameter modelID: resolves the user's model family to a concrete model ID (see `ClaudeModelResolver`).
    public static func makeTransport(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        modelID: @escaping @Sendable (ClaudeModelFamily) -> String = { $0.fallbackModelID },
        session: any HTTPDataSending = URLSession.shared
    ) -> @Sendable (String, String, Int, ClaudeModelFamily) async throws -> String {
        return { systemPrompt, userText, _, family in
            let apiKey = try apiKeyProvider()
            var body: [String: Any] = [
                "model": modelID(family),
                "max_tokens": AnthropicDefaults.maxTokens,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": userText]
                ]
            ]
            let minimalBody = body
            // Text correction needs no reasoning — thinking off keeps latency low.
            body["thinking"] = ["type": family.thinkingOffType]
            body["output_config"] = ["effort": "low"]

            FileLog.log("ClaudeAPITransport — family=\(family.rawValue) model=\(body["model"] ?? "")")
            do {
                return try await send(body, apiKey: apiKey, session: session)
            } catch ClaudeAPIError.httpError(400, let errorBody) {
                // A newer model may reject these options — retry once with the bare request.
                FileLog.log("ClaudeAPITransport — HTTP 400 for \(body["model"] ?? ""), retrying minimal request: \(errorBody)")
                return try await send(minimalBody, apiKey: apiKey, session: session)
            }
        }
    }

    private static func send(_ body: [String: Any], apiKey: String, session: any HTTPDataSending) async throws -> String {
        var request = URLRequest(url: AnthropicDefaults.apiURL)
        request.httpMethod = "POST"
        request.setValue(AnthropicDefaults.Headers.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: AnthropicDefaults.Headers.apiKey)
        request.setValue(AnthropicDefaults.apiVersion, forHTTPHeaderField: AnthropicDefaults.Headers.version)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        // Newer models may put (empty) thinking blocks before the text block.
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw ClaudeAPIError.parseError
        }

        return text
    }
}

private extension ClaudeModelFamily {
    /// Haiku accepts `disabled`; Sonnet 5.5 rejects it and uses `between_tools` instead.
    var thinkingOffType: String {
        switch self {
        case .haiku: "disabled"
        case .sonnet: "between_tools"
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
