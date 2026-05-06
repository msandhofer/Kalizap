import Foundation
import CryptoKit
import os

public enum EncryptedCredentialStoreError: Error, LocalizedError {
    case itemNotFound
    case decryptionFailed
    case invalidFileFormat
    case ioError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Credential nicht gefunden."
        case .decryptionFailed: return "Credential konnte nicht entschlüsselt werden (Gerät, Nutzer oder App-Version verändert?)."
        case .invalidFileFormat: return "Credential-Datei hat ungültiges Format."
        case .ioError(let underlying): return "Dateizugriffsfehler: \(underlying.localizedDescription)"
        }
    }
}

public final class EncryptedCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
    private let baseDirectory: URL
    private let identity: any HardwareIdentityProviding
    private let appSecret: Data
    private let lock = OSAllocatedUnfairLock()

    private static let saltSize = 32
    private static let derivedKeySize = 32

    public init(
        baseDirectory: URL,
        identity: any HardwareIdentityProviding,
        appSecret: Data
    ) {
        self.baseDirectory = baseDirectory
        self.identity = identity
        self.appSecret = appSecret
    }

    public func store(_ value: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let salt = Data((0..<Self.saltSize).map { _ in UInt8.random(in: 0...255) })
        let key = try deriveKey(salt: salt, account: account)
        let plaintext = Data(value.utf8)

        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw EncryptedCredentialStoreError.decryptionFailed
        }

        var fileBytes = Data()
        fileBytes.append(salt)
        fileBytes.append(combined)

        try ensureBaseDirectoryExists()
        let url = fileURL(for: account)
        try writeAtomicallyWithRestrictivePermissions(fileBytes, to: url)
    }

    public func retrieve(for account: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: account)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EncryptedCredentialStoreError.itemNotFound
        }

        let fileBytes: Data
        do {
            fileBytes = try Data(contentsOf: url)
        } catch {
            throw EncryptedCredentialStoreError.ioError(underlying: error)
        }

        guard fileBytes.count > Self.saltSize else {
            throw EncryptedCredentialStoreError.invalidFileFormat
        }

        let salt = fileBytes.prefix(Self.saltSize)
        let combined = fileBytes.suffix(from: Self.saltSize)

        let key = try deriveKey(salt: Data(salt), account: account)

        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw EncryptedCredentialStoreError.invalidFileFormat
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw EncryptedCredentialStoreError.decryptionFailed
        }

        guard let result = String(data: plaintext, encoding: .utf8) else {
            throw EncryptedCredentialStoreError.invalidFileFormat
        }
        return result
    }

    public func delete(for account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: account)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw EncryptedCredentialStoreError.ioError(underlying: error)
            }
        }
    }

    // MARK: - Private

    private func fileURL(for account: String) -> URL {
        baseDirectory.appendingPathComponent("\(account).enc", isDirectory: false)
    }

    private func ensureBaseDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw EncryptedCredentialStoreError.ioError(underlying: error)
        }
    }

    private func writeAtomicallyWithRestrictivePermissions(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw EncryptedCredentialStoreError.ioError(underlying: error)
        }
    }

    private func deriveKey(salt: Data, account: String) throws -> SymmetricKey {
        var ikm = Data()
        let deviceID = try identity.deviceIdentifier()
        ikm.append(Data(deviceID.utf8))
        ikm.append(0x00)
        ikm.append(Data(identity.userName().utf8))
        ikm.append(0x00)
        ikm.append(appSecret)

        let info = Data(account.utf8)

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: info,
            outputByteCount: Self.derivedKeySize
        )
        return derived
    }
}
