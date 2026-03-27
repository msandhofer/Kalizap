import Foundation

@Observable @MainActor
public final class APIKeyManager {
    public private(set) var status: APIKeyStatus = .missing

    private let keychain: any KeychainServiceProtocol
    private let validator: any APIKeyValidating
    nonisolated private static let account = "anthropic-api-key"

    public init(keychain: any KeychainServiceProtocol, validator: any APIKeyValidating) {
        self.keychain = keychain
        self.validator = validator
    }

    public func setKey(_ key: String) throws {
        try keychain.store(key, for: Self.account)
    }

    public func resolveKey() throws -> String {
        try keychain.retrieve(for: Self.account)
    }

    nonisolated public func resolveKeySendable() throws -> String {
        try keychain.retrieve(for: Self.account)
    }

    public func deleteKey() throws {
        try keychain.delete(for: Self.account)
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
