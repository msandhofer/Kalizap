import Foundation

/// Model family the user picks in the settings. The concrete model ID is resolved at runtime,
/// because the Anthropic API has no "latest Haiku" alias — IDs from 4.6 on are fixed snapshots (#57).
public enum ClaudeModelFamily: String, Codable, CaseIterable, Sendable {
    case haiku
    case sonnet

    public var displayName: String {
        switch self {
        case .haiku: "Neuestes Haiku – schnell, günstig"
        case .sonnet: "Neuestes Sonnet – gründlicher, langsamer, teurer"
        }
    }

    /// Used until the models list has been fetched successfully once.
    public var fallbackModelID: String {
        switch self {
        case .haiku: "claude-haiku-5-5"
        case .sonnet: "claude-sonnet-5-5"
        }
    }

    var idPrefix: String { "claude-\(rawValue)-" }
}

/// Resolves a model family to the newest concrete model ID via `GET /v1/models`, cached in UserDefaults.
public final class ClaudeModelResolver: @unchecked Sendable {
    private static let cacheKey = "resolvedClaudeModelIDs"

    private let defaults: UserDefaults
    private let session: any HTTPDataSending
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, session: any HTTPDataSending = URLSession.shared) {
        self.defaults = defaults
        self.session = session
    }

    public func modelID(for family: ClaudeModelFamily) -> String {
        lock.withLock {
            let cached = defaults.dictionary(forKey: Self.cacheKey) as? [String: String]
            return cached?[family.rawValue] ?? family.fallbackModelID
        }
    }

    /// Fetches the models list and updates the cache. Failures keep the previous cache.
    public func refresh(apiKey: String) async {
        var request = URLRequest(url: AnthropicDefaults.modelsURL)
        request.setValue(apiKey, forHTTPHeaderField: AnthropicDefaults.Headers.apiKey)
        request.setValue(AnthropicDefaults.apiVersion, forHTTPHeaderField: AnthropicDefaults.Headers.version)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileLog.log("ClaudeModelResolver — models list HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let ids = try Self.newestModelIDs(fromModelsResponse: data)
            guard !ids.isEmpty else { return }
            store(ids)
            FileLog.log("ClaudeModelResolver — resolved \(ids)")
        } catch {
            FileLog.log("ClaudeModelResolver — models list failed: \(error)")
        }
    }

    private func store(_ ids: [ClaudeModelFamily: String]) {
        lock.withLock {
            var cached = (defaults.dictionary(forKey: Self.cacheKey) as? [String: String]) ?? [:]
            for (family, id) in ids { cached[family.rawValue] = id }
            defaults.set(cached, forKey: Self.cacheKey)
        }
    }

    static func newestModelIDs(fromModelsResponse data: Data) throws -> [ClaudeModelFamily: String] {
        struct Model: Decodable { let id: String; let created_at: String }
        struct Page: Decodable { let data: [Model] }
        let models = try JSONDecoder().decode(Page.self, from: data).data

        var result: [ClaudeModelFamily: String] = [:]
        for family in ClaudeModelFamily.allCases {
            // RFC 3339 timestamps in one format sort correctly as strings.
            let newest = models
                .filter { $0.id.hasPrefix(family.idPrefix) }
                .max { $0.created_at < $1.created_at }
            if let newest { result[family] = newest.id }
        }
        return result
    }
}
