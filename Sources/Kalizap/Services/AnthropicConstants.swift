import Foundation

public enum AnthropicDefaults {
    public static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelsURL = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!
    public static let apiVersion = "2023-06-01"
    public static let maxTokens = 4096

    public enum Headers {
        public static let apiKey = "x-api-key"
        public static let version = "anthropic-version"
        public static let contentType = "application/json"
    }
}
