import Foundation
import os

public enum APIKeyError: Error, LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        "Kein API-Key konfiguriert. Bitte in den Einstellungen hinterlegen."
    }
}

@Observable @MainActor
public final class APIKeyManager {
    public private(set) var status: APIKeyStatus = .missing

    /// Cached key visible on MainActor (for UI, e.g. Settings text field).
    public private(set) var cachedKey: String?

    private let keychain: any KeychainServiceProtocol
    private let validator: any APIKeyValidating
    nonisolated private static let account = "anthropic-api-key"

    /// Thread-safe cache for nonisolated access from API transport closures.
    private let keyCache = OSAllocatedUnfairLock<String?>(initialState: nil)

    public init(keychain: any KeychainServiceProtocol, validator: any APIKeyValidating) {
        self.keychain = keychain
        self.validator = validator
    }

    public func setKey(_ key: String) throws {
        try keychain.store(key, for: Self.account)
        cachedKey = key
        keyCache.withLock { $0 = key }
    }

    public func resolveKey() throws -> String {
        if let cachedKey { return cachedKey }
        let key = try keychain.retrieve(for: Self.account)
        cachedKey = key
        keyCache.withLock { $0 = key }
        return key
    }

    /// Thread-safe key access for Sendable closures (API transport).
    /// Returns the cached key without hitting the keychain.
    nonisolated public func resolveKeySendable() throws -> String {
        if let key = keyCache.withLock({ $0 }) { return key }
        // Fallback to keychain only if cache was never populated (should not happen after bootstrap)
        let key = try keychain.retrieve(for: Self.account)
        keyCache.withLock { $0 = key }
        return key
    }

    public func deleteKey() throws {
        try keychain.delete(for: Self.account)
        cachedKey = nil
        keyCache.withLock { $0 = nil }
        status = .missing
    }

    public func validate() async {
        guard let key = try? resolveKey() else {
            status = .missing
            return
        }
        status = .validating
        do {
            try await validator.validate(apiKey: key)
            status = .valid
        } catch {
            status = .invalid(error.localizedDescription)
        }
    }
}
