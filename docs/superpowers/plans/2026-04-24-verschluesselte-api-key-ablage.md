# Verschlüsselte API-Key-Ablage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den Anthropic-API-Key nicht mehr in der macOS-Keychain, sondern als AES-GCM-verschlüsselte Datei im Application-Support-Verzeichnis ablegen. Der Verschlüsselungs-Schlüssel wird via HKDF aus `IOPlatformUUID`, `NSUserName()` und einem Build-Time-injizierten App-Secret abgeleitet.

**Architecture:** Protokoll-basierter Austausch der bestehenden `KeychainService`-Implementierung gegen `EncryptedCredentialStore`. Die Account-basierte Signatur (`store/retrieve/delete`) des Protocols bleibt erhalten. Hardware-Identität wird über `HardwareIdentityProviding` abstrahiert → deterministisch testbar. Das App-Secret liegt in einer gitignored Swift-Datei, die per Shell-Script einmalig generiert wird.

**Tech Stack:** Swift 6.2, CryptoKit (AES-GCM, HKDF-SHA256), IOKit (IOPlatformUUID), Foundation (FileManager), XCTest.

---

## Bedrohungsmodell

**Schützen gegen:**
- Ungezielte Stealer-Malware, die Home-Verzeichnis nach Klartext-Pattern durchsucht
- Diebstahl einzelner Backup-/Datei-Kopien (Time Machine auf fremder Platte, kopierter App-Support-Ordner)
- Kreuz-Gerät-Übertragung (Datei funktioniert auf anderem Gerät nicht)

**Nicht schützen gegen:**
- Angreifer mit vollem Gerätezugriff (kann Binary, UUID, Username, Datei alle lesen)
- Gezielte Reverse-Engineering-Angriffe (App-Secret via `strings` extrahierbar)
- Keylogger / Memory-Dump zur Laufzeit

## File Structure

### Neue Dateien

| Pfad | Verantwortung |
|---|---|
| `Sources/DerFluisterer/Services/HardwareIdentityProvider.swift` | Protocol `HardwareIdentityProviding` + Production-Impl (liest `IOPlatformUUID` via IOKit, `NSUserName()` via Foundation) |
| `Sources/DerFluisterer/Services/EncryptedCredentialStore.swift` | `CredentialStoreProtocol`-Impl: AES-GCM-Ver-/Entschlüsselung, HKDF-Key-Derivation, File-Persistenz |
| `Sources/DerFluistererApp/AppSecret.swift` | **Gitignored.** 32-Byte Random-Secret als `static let`. Wird per Script einmalig erzeugt. |
| `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift` | Roundtrip-, Persistenz-, Mismatch-, Delete-Tests mit Fake-Identity |
| `Scripts/generate-app-secret.sh` | Einmalige Secret-Generierung (scheitert, wenn Datei schon existiert — kein stiller Rotations-Bug) |
| `docs/build-secret.md` | Operations-Doku: Generieren, Sichern, Verhalten bei Verlust |
| `docs/security.md` | Öffentliche Security-Dokumentation: Threat-Modell, Design, akzeptierte Trade-offs |

### Zu modifizierende Dateien

| Pfad | Änderung |
|---|---|
| `Sources/DerFluisterer/Modules/SettingsManager.swift` | Protocol umbenennen: `KeychainServiceProtocol` → `CredentialStoreProtocol`. Parameter-Label `keychain:` → `credentialStore:` in `SettingsManager.init`. |
| `Sources/DerFluisterer/Services/APIKeyManager.swift` | Parameter-Typ + Label: `keychain: any KeychainServiceProtocol` → `credentialStore: any CredentialStoreProtocol`. Property intern `keychain` → `credentialStore`. |
| `Sources/DerFluistererApp/DerFluistererApp.swift` | Wiring: `KeychainService()` → `EncryptedCredentialStore(fileURL:identity:appSecret:)` mit Application-Support-Pfad, `ProductionHardwareIdentity()`, `AppSecret.bytes`. |
| `.gitignore` | Zeile `Sources/DerFluistererApp/AppSecret.swift` hinzufügen. |
| `README.md` | Abschnitt "Build from source" erweitern um Schritt `./Scripts/generate-app-secret.sh` vor erstem Build. |

### Zu löschende Dateien

| Pfad | Grund |
|---|---|
| `Sources/DerFluisterer/Services/KeychainService.swift` | Ersetzt durch `EncryptedCredentialStore` |
| `Tests/DerFluistererTests/KeychainServiceTests.swift` | Ersetzt durch `EncryptedCredentialStoreTests` |

## File-Format der Credentials-Datei

```
[32 Byte Salt][SealedBox.combined]
```

Wobei `SealedBox.combined` = `[12 Byte Nonce][Ciphertext n Byte][16 Byte GCM-Tag]`.

Keine Magic-Bytes, kein Header — Datei sieht wie zufälliger Binärmüll aus. Der Salt ist pro Schreibvorgang random → identische Klartexte ergeben unterschiedliche Ciphertexte.

## Key-Derivation

```
ikm  = IOPlatformUUID (UTF-8 Bytes) ++ 0x00 ++ NSUserName() (UTF-8 Bytes) ++ 0x00 ++ AppSecret (32 Byte)
salt = random pro Write, 32 Byte, im File
info = account.utf8 (z. B. "anthropic-api-key")
key  = HKDF-SHA256(ikm, salt, info, 32 Byte)
```

Der `0x00`-Separator verhindert, dass verschiedene Input-Splits denselben konkatenierten String ergeben. Ein Angreifer, der ein bestimmtes `ikm` errät, bekommt jedes Mal einen anderen Key (wegen Salt). `info = account` bindet den Key an den Account-Namen → verschiedene Accounts ergeben verschiedene Keys, selbst wenn die restlichen Inputs identisch sind.

---

## Task 0: Repository-Setup (gitignore + AppSecret-Script + AppSecret.swift)

**Files:**
- Create: `Scripts/generate-app-secret.sh`
- Create: `Sources/DerFluistererApp/AppSecret.swift` (lokal, gitignored)
- Modify: `.gitignore`

- [ ] **Step 1: .gitignore um AppSecret.swift erweitern**

Datei: `.gitignore` — ans Ende anfügen:

```
# Build-Time-Secret für API-Key-Verschlüsselung (siehe docs/build-secret.md)
Sources/DerFluistererApp/AppSecret.swift
```

- [ ] **Step 2: Shell-Script zur Secret-Generierung schreiben**

Datei: `Scripts/generate-app-secret.sh` (neu, ausführbar):

```bash
#!/usr/bin/env bash
# Generiert einmalig Sources/DerFluistererApp/AppSecret.swift mit 32 Byte Random-Secret.
# Scheitert hart, wenn die Datei bereits existiert — keine stille Rotation.
# Siehe docs/build-secret.md.

set -euo pipefail

TARGET="Sources/DerFluistererApp/AppSecret.swift"

if [ -f "$TARGET" ]; then
  echo "FEHLER: $TARGET existiert bereits. Nicht überschrieben." >&2
  echo "Soll das Secret absichtlich rotiert werden: Datei manuell löschen und Script neu ausführen." >&2
  echo "Achtung: Rotation invalidiert alle bestehenden verschlüsselten Credentials." >&2
  exit 1
fi

SECRET=$(openssl rand -base64 32)

cat > "$TARGET" <<EOF
// Auto-generiert von Scripts/generate-app-secret.sh. NICHT committen.
// Siehe docs/build-secret.md für Hintergrund und Backup-Pflicht.
import Foundation

enum AppSecret {
    static let bytes: Data = Data(base64Encoded: "$SECRET")!
}
EOF

echo "OK: $TARGET generiert."
echo "WICHTIG: Dieses Secret sichern (z. B. Passwortmanager-Eintrag)."
echo "         Bei Verlust müssen alle Nutzer ihren API-Key neu eintragen."
```

Script ausführbar machen: `chmod +x Scripts/generate-app-secret.sh`

- [ ] **Step 3: Script einmalig ausführen, AppSecret.swift erzeugen**

Run: `./Scripts/generate-app-secret.sh`
Expected: Ausgabe endet mit `OK: Sources/DerFluistererApp/AppSecret.swift generiert.`

Verifikation: `ls -la Sources/DerFluistererApp/AppSecret.swift` zeigt Datei existiert.

- [ ] **Step 4: Prüfen, dass Datei gitignored ist**

Run: `git status --short`
Expected: **Keine** Zeile mit `AppSecret.swift`. Nur `.gitignore` und `Scripts/generate-app-secret.sh` als neu/geändert.

- [ ] **Step 5: Zweiter Script-Aufruf scheitert hart**

Run: `./Scripts/generate-app-secret.sh` (zum zweiten Mal)
Expected: Exit-Code ≠ 0, Ausgabe enthält `FEHLER: ... existiert bereits.`

- [ ] **Step 6: Commit (partial — nur Script + gitignore, AppSecret.swift bleibt außerhalb)**

```bash
git add .gitignore Scripts/generate-app-secret.sh
git commit -m "$(cat <<'EOF'
chore(#44): Build-Time-Secret-Mechanismus vorbereiten

- Scripts/generate-app-secret.sh: einmalige Secret-Generierung, scheitert bei existierender Datei
- .gitignore: AppSecret.swift ausschließen
- AppSecret.swift lokal generiert (nicht committed)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: `HardwareIdentityProviding` — Protokoll und Production-Impl

**Files:**
- Create: `Sources/DerFluisterer/Services/HardwareIdentityProvider.swift`
- Test: keine dedizierten Tests — Production-Impl ist ein Wrapper über IOKit/Foundation, nicht unit-testbar ohne Hardware. Fake-Impl wird in Task 2+ als inline Helper-Klasse in Tests erstellt und dadurch exerciert.

- [ ] **Step 1: Datei mit Protokoll und Production-Impl schreiben**

Datei: `Sources/DerFluisterer/Services/HardwareIdentityProvider.swift`:

```swift
import Foundation
import IOKit

public protocol HardwareIdentityProviding: Sendable {
    /// Stabile Geräte-Identität. Auf macOS: IOPlatformUUID.
    func deviceIdentifier() throws -> String

    /// User-Account-Name auf diesem Gerät.
    func userName() -> String
}

public enum HardwareIdentityError: Error, LocalizedError {
    case platformUUIDUnavailable

    public var errorDescription: String? {
        switch self {
        case .platformUUIDUnavailable:
            return "IOPlatformUUID konnte nicht gelesen werden."
        }
    }
}

public final class ProductionHardwareIdentity: HardwareIdentityProviding {
    public init() {}

    public func deviceIdentifier() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else {
            throw HardwareIdentityError.platformUUIDUnavailable
        }
        defer { IOObjectRelease(service) }

        guard let uuidCF = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            throw HardwareIdentityError.platformUUIDUnavailable
        }
        return uuidCF
    }

    public func userName() -> String {
        NSUserName()
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `swift build`
Expected: Build läuft erfolgreich durch, keine Fehler.

- [ ] **Step 3: Commit (Teil 1 der Implementierung — Protokoll steht)**

Noch nicht committen. Wir committen als größeren Block zusammen mit Task 2+, damit der Commit ein funktionierendes Feature enthält. Nächster Task baut darauf auf.

---

## Task 2: `EncryptedCredentialStore` — Roundtrip in einer Instanz

**Files:**
- Create: `Sources/DerFluisterer/Services/EncryptedCredentialStore.swift`
- Test: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`

- [ ] **Step 1: Test-Datei mit Fake-Identity und Roundtrip-Test schreiben**

Datei: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`:

```swift
import XCTest
@testable import DerFluisterer

final class EncryptedCredentialStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ecs-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func makeSUT(
        identity: any HardwareIdentityProviding = FakeIdentity(deviceID: "test-device", userName: "test-user"),
        appSecret: Data = Data(repeating: 0xAB, count: 32)
    ) -> EncryptedCredentialStore {
        EncryptedCredentialStore(
            baseDirectory: tempDir,
            identity: identity,
            appSecret: appSecret
        )
    }

    func test_storeAndRetrieve_roundTripInSameInstance() throws {
        let sut = makeSUT()

        try sut.store("sk-ant-test-123", for: "anthropic-api-key")
        let retrieved = try sut.retrieve(for: "anthropic-api-key")

        XCTAssertEqual(retrieved, "sk-ant-test-123")
    }
}

private struct FakeIdentity: HardwareIdentityProviding {
    let deviceID: String
    let userName: String

    func deviceIdentifier() throws -> String { deviceID }
    func userName() -> String { userName }
}
```

- [ ] **Step 2: Test ausführen — muss fehlschlagen, da Typ noch nicht existiert**

Run: `swift test --filter EncryptedCredentialStoreTests/test_storeAndRetrieve_roundTripInSameInstance`
Expected: Compile-Fehler `cannot find 'EncryptedCredentialStore' in scope`.

- [ ] **Step 3: Minimale Implementation schreiben**

Datei: `Sources/DerFluisterer/Services/EncryptedCredentialStore.swift`:

```swift
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
```

**Wichtig:** Diese Datei referenziert `CredentialStoreProtocol`, das es noch nicht gibt — es wird in Task 9 eingeführt (Umbenennung von `KeychainServiceProtocol`). Bis dahin nutzen wir temporär das alte `KeychainServiceProtocol`. Ändere in der Zeile `public final class EncryptedCredentialStore: CredentialStoreProtocol, @unchecked Sendable {`  den Typ temporär zu `KeychainServiceProtocol`:

```swift
public final class EncryptedCredentialStore: KeychainServiceProtocol, @unchecked Sendable {
```

Der Build läuft dadurch sauber. In Task 9 wird das dann final umbenannt.

- [ ] **Step 4: Test ausführen, muss passen**

Run: `swift test --filter EncryptedCredentialStoreTests/test_storeAndRetrieve_roundTripInSameInstance`
Expected: Test passiert grün.

---

## Task 3: Persistenz-Test über zwei Instanzen

**Files:**
- Modify: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`

- [ ] **Step 1: Neuen Test schreiben**

In `EncryptedCredentialStoreTests.swift` vor dem letzten `}` der Test-Klasse anfügen:

```swift
func test_storeAndRetrieve_persistsAcrossInstances() throws {
    let identity = FakeIdentity(deviceID: "persist-device", userName: "persist-user")
    let secret = Data(repeating: 0xCD, count: 32)

    let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secret)
    try writer.store("sk-ant-persist-456", for: "anthropic-api-key")

    let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secret)
    let retrieved = try reader.retrieve(for: "anthropic-api-key")

    XCTAssertEqual(retrieved, "sk-ant-persist-456")
}
```

- [ ] **Step 2: Test ausführen**

Run: `swift test --filter EncryptedCredentialStoreTests/test_storeAndRetrieve_persistsAcrossInstances`
Expected: Passiert grün. (Impl aus Task 2 deckt das bereits ab.)

---

## Task 4: Identity-Mismatch-Test (anderes Device/User → Fehler)

**Files:**
- Modify: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`

- [ ] **Step 1: Test schreiben**

In Test-Klasse anfügen:

```swift
func test_retrieve_failsWhenDeviceIdentifierDiffers() throws {
    let secret = Data(repeating: 0xEE, count: 32)
    let writerIdentity = FakeIdentity(deviceID: "device-A", userName: "user-X")
    let readerIdentity = FakeIdentity(deviceID: "device-B", userName: "user-X")

    let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: writerIdentity, appSecret: secret)
    try writer.store("sk-ant-device-bound", for: "anthropic-api-key")

    let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: readerIdentity, appSecret: secret)

    XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
        guard case EncryptedCredentialStoreError.decryptionFailed = error else {
            XCTFail("Expected decryptionFailed, got \(error)")
            return
        }
    }
}

func test_retrieve_failsWhenUserNameDiffers() throws {
    let secret = Data(repeating: 0xFF, count: 32)
    let writerIdentity = FakeIdentity(deviceID: "device-same", userName: "alice")
    let readerIdentity = FakeIdentity(deviceID: "device-same", userName: "bob")

    let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: writerIdentity, appSecret: secret)
    try writer.store("sk-ant-user-bound", for: "anthropic-api-key")

    let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: readerIdentity, appSecret: secret)

    XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
        guard case EncryptedCredentialStoreError.decryptionFailed = error else {
            XCTFail("Expected decryptionFailed, got \(error)")
            return
        }
    }
}
```

- [ ] **Step 2: Tests ausführen**

Run: `swift test --filter EncryptedCredentialStoreTests/test_retrieve_failsWhenDeviceIdentifierDiffers`
Expected: PASS.

Run: `swift test --filter EncryptedCredentialStoreTests/test_retrieve_failsWhenUserNameDiffers`
Expected: PASS.

---

## Task 5: AppSecret-Mismatch-Test

**Files:**
- Modify: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`

- [ ] **Step 1: Test schreiben**

In Test-Klasse anfügen:

```swift
func test_retrieve_failsWhenAppSecretDiffers() throws {
    let identity = FakeIdentity(deviceID: "same-device", userName: "same-user")
    let secretA = Data(repeating: 0x11, count: 32)
    let secretB = Data(repeating: 0x22, count: 32)

    let writer = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secretA)
    try writer.store("sk-ant-secret-bound", for: "anthropic-api-key")

    let reader = EncryptedCredentialStore(baseDirectory: tempDir, identity: identity, appSecret: secretB)

    XCTAssertThrowsError(try reader.retrieve(for: "anthropic-api-key")) { error in
        guard case EncryptedCredentialStoreError.decryptionFailed = error else {
            XCTFail("Expected decryptionFailed, got \(error)")
            return
        }
    }
}
```

- [ ] **Step 2: Test ausführen**

Run: `swift test --filter EncryptedCredentialStoreTests/test_retrieve_failsWhenAppSecretDiffers`
Expected: PASS.

---

## Task 6: retrieve-ohne-store wirft + Overwrite-Test + delete-Test

**Files:**
- Modify: `Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift`

- [ ] **Step 1: Tests schreiben**

In Test-Klasse anfügen:

```swift
func test_retrieve_throwsItemNotFoundWhenNoFile() {
    let sut = makeSUT()

    XCTAssertThrowsError(try sut.retrieve(for: "nonexistent-account")) { error in
        guard case EncryptedCredentialStoreError.itemNotFound = error else {
            XCTFail("Expected itemNotFound, got \(error)")
            return
        }
    }
}

func test_store_overwritesExistingValue() throws {
    let sut = makeSUT()

    try sut.store("old-key", for: "anthropic-api-key")
    try sut.store("new-key", for: "anthropic-api-key")

    let retrieved = try sut.retrieve(for: "anthropic-api-key")
    XCTAssertEqual(retrieved, "new-key")
}

func test_delete_removesStoredValue() throws {
    let sut = makeSUT()

    try sut.store("will-be-deleted", for: "anthropic-api-key")
    try sut.delete(for: "anthropic-api-key")

    XCTAssertThrowsError(try sut.retrieve(for: "anthropic-api-key")) { error in
        guard case EncryptedCredentialStoreError.itemNotFound = error else {
            XCTFail("Expected itemNotFound, got \(error)")
            return
        }
    }
}

func test_delete_isNoOpWhenFileMissing() throws {
    let sut = makeSUT()
    // Keine Store-Aktion vorher
    XCTAssertNoThrow(try sut.delete(for: "nonexistent"))
}
```

- [ ] **Step 2: Alle Tests der Suite ausführen**

Run: `swift test --filter EncryptedCredentialStoreTests`
Expected: **8 Tests grün** (Task 2 + 3 + 4 + 5 + 6 kombiniert = `roundTrip`, `persistsAcross`, `deviceDiffers`, `userDiffers`, `secretDiffers`, `itemNotFound`, `overwrites`, `deleteRemoves`, `deleteNoOp` — 9 Tests).

- [ ] **Step 3: Zwischen-Commit (EncryptedCredentialStore fertig, noch nicht verdrahtet)**

```bash
git add Sources/DerFluisterer/Services/HardwareIdentityProvider.swift
git add Sources/DerFluisterer/Services/EncryptedCredentialStore.swift
git add Tests/DerFluistererTests/EncryptedCredentialStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(#44): EncryptedCredentialStore mit AES-GCM + HKDF

- HardwareIdentityProviding: Protocol + ProductionHardwareIdentity (IOPlatformUUID + NSUserName)
- EncryptedCredentialStore: AES-GCM verschlüsselte File-Persistenz, HKDF-SHA256 Key-Derivation
- Key-Material: IOPlatformUUID || NSUserName || AppSecret, pro Write random Salt
- 9 Tests (Roundtrip, Persistenz, Device-/User-/Secret-Mismatch, NotFound, Overwrite, Delete)
- Temporär als KeychainServiceProtocol-Impl (Umbenennung folgt in nächstem Commit)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Protocol-Umbenennung `KeychainServiceProtocol` → `CredentialStoreProtocol`

**Files:**
- Modify: `Sources/DerFluisterer/Modules/SettingsManager.swift`
- Modify: `Sources/DerFluisterer/Services/APIKeyManager.swift`
- Modify: `Sources/DerFluisterer/Services/EncryptedCredentialStore.swift`

- [ ] **Step 1: `SettingsManager.swift` — Protocol umbenennen und Parameter-Label anpassen**

In `Sources/DerFluisterer/Modules/SettingsManager.swift`:

**Alt (Zeile ~175):**
```swift
public protocol KeychainServiceProtocol: Sendable {
    func store(_ value: String, for account: String) throws
    func retrieve(for account: String) throws -> String
    func delete(for account: String) throws
}
```

**Neu:**
```swift
public protocol CredentialStoreProtocol: Sendable {
    func store(_ value: String, for account: String) throws
    func retrieve(for account: String) throws -> String
    func delete(for account: String) throws
}
```

**Alt (Zeile ~210):**
```swift
public init(defaults: UserDefaults = .standard, keychain: any KeychainServiceProtocol, apiKeyValidator: any APIKeyValidating, launchAtLogin: any LaunchAtLoginProtocol = NoOpLaunchAtLogin()) {
    self.defaults = defaults
    self.launchAtLogin = launchAtLogin
    self.apiKey = APIKeyManager(keychain: keychain, validator: apiKeyValidator)
```

**Neu:**
```swift
public init(defaults: UserDefaults = .standard, credentialStore: any CredentialStoreProtocol, apiKeyValidator: any APIKeyValidating, launchAtLogin: any LaunchAtLoginProtocol = NoOpLaunchAtLogin()) {
    self.defaults = defaults
    self.launchAtLogin = launchAtLogin
    self.apiKey = APIKeyManager(credentialStore: credentialStore, validator: apiKeyValidator)
```

- [ ] **Step 2: `APIKeyManager.swift` — Parameter-Typ, -Label und interne Property umbenennen**

In `Sources/DerFluisterer/Services/APIKeyManager.swift`:

**Alt (Zeile ~19):**
```swift
private let keychain: any KeychainServiceProtocol
```
**Neu:**
```swift
private let credentialStore: any CredentialStoreProtocol
```

**Alt (Zeile ~26):**
```swift
public init(keychain: any KeychainServiceProtocol, validator: any APIKeyValidating) {
    self.keychain = keychain
```
**Neu:**
```swift
public init(credentialStore: any CredentialStoreProtocol, validator: any APIKeyValidating) {
    self.credentialStore = credentialStore
```

Alle weiteren Referenzen `self.keychain` und `keychain.` im File durch `self.credentialStore` und `credentialStore.` ersetzen. Konkret (Zeilen ~32, 39, 50, 57):

```swift
try credentialStore.store(key, for: Self.account)
// ...
let key = try credentialStore.retrieve(for: Self.account)
// ...
let key = try credentialStore.retrieve(for: Self.account)
// ...
try credentialStore.delete(for: Self.account)
```

- [ ] **Step 3: `EncryptedCredentialStore.swift` — temporären Protocol-Typ final umstellen**

In `Sources/DerFluisterer/Services/EncryptedCredentialStore.swift`:

**Alt:**
```swift
public final class EncryptedCredentialStore: KeychainServiceProtocol, @unchecked Sendable {
```

**Neu:**
```swift
public final class EncryptedCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
```

- [ ] **Step 4: Build läuft, aber KeychainService.swift/Tests referenzieren nun ungültigen Typ. Das wird in Task 8 aufgeräumt. Skip, weiter zu Task 8 ohne Build-Check.**

---

## Task 8: Altlasten entfernen (KeychainService + Tests)

**Files:**
- Delete: `Sources/DerFluisterer/Services/KeychainService.swift`
- Delete: `Tests/DerFluistererTests/KeychainServiceTests.swift`

- [ ] **Step 1: Altdateien löschen**

Run:
```bash
rm Sources/DerFluisterer/Services/KeychainService.swift
```
Run:
```bash
rm Tests/DerFluistererTests/KeychainServiceTests.swift
```

- [ ] **Step 2: Build verifizieren — es wird jetzt fehlschlagen am DerFluistererApp, weil der noch `KeychainService()` aufruft**

Run: `swift build`
Expected: Fehler in `Sources/DerFluistererApp/DerFluistererApp.swift` — `cannot find 'KeychainService' in scope`.

Das wird in Task 9 behoben.

---

## Task 9: App-Dependency-Wiring umstellen

**Files:**
- Modify: `Sources/DerFluistererApp/DerFluistererApp.swift`

- [ ] **Step 1: Wiring auf EncryptedCredentialStore umstellen**

In `Sources/DerFluistererApp/DerFluistererApp.swift` den `init()`-Block ersetzen:

**Alt (Zeile 9–22):**
```swift
init() {
    let settings = SettingsManager(
        keychain: KeychainService(),
        apiKeyValidator: AnthropicAPIKeyValidator(),
        launchAtLogin: LaunchAtLoginService()
    )
    let container = try! ModelContainer(
        for: DictationRecord.self,
        migrationPlan: DictationMigrationPlan.self
    )
    let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
    _appState = State(initialValue: AppState(settings: settings, store: store))
    FileLog.log("App.init completed — language=\(settings.audio.language.rawValue)")
}
```

**Neu:**
```swift
init() {
    let credentialStore = Self.makeCredentialStore()
    let settings = SettingsManager(
        credentialStore: credentialStore,
        apiKeyValidator: AnthropicAPIKeyValidator(),
        launchAtLogin: LaunchAtLoginService()
    )
    let container = try! ModelContainer(
        for: DictationRecord.self,
        migrationPlan: DictationMigrationPlan.self
    )
    let store: any DictationStoring = DictationStoreImpl(modelContainer: container)
    _appState = State(initialValue: AppState(settings: settings, store: store))
    FileLog.log("App.init completed — language=\(settings.audio.language.rawValue)")
}

private static func makeCredentialStore() -> EncryptedCredentialStore {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let baseDir = appSupport
        .appendingPathComponent("DerFluisterer", isDirectory: true)
        .appendingPathComponent("credentials", isDirectory: true)
    return EncryptedCredentialStore(
        baseDirectory: baseDir,
        identity: ProductionHardwareIdentity(),
        appSecret: AppSecret.bytes
    )
}
```

- [ ] **Step 2: Build verifizieren**

Run: `swift build`
Expected: Build läuft grün durch.

- [ ] **Step 3: Alle bestehenden Tests laufen lassen, um Regressionen zu finden**

Run: `swift test`
Expected: Alle Tests passieren. Einige Test-Files (z. B. `SettingsManagerTests`, `APIKeyValidatorTests`) nutzen Mocks, die das alte Protocol-Label `keychain:` erwarten. Falls Fehler: in den Test-Helpers und Tests alle Aufrufe von `SettingsManager(... keychain:` und `APIKeyManager(keychain:` durch `credentialStore:` ersetzen.

**Falls Test-Fehler:** Grep nach `keychain:` in Tests-Ordner und korrigieren:

Run: `grep -rln "keychain:" Tests/`

Für jede Fundstelle: ersetze `keychain:` durch `credentialStore:`.

Nochmal `swift test`.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "$(cat <<'EOF'
refactor(#44): Protocol-Umbenennung und App-Wiring auf EncryptedCredentialStore

- KeychainServiceProtocol → CredentialStoreProtocol
- APIKeyManager + SettingsManager: Parameter-Label keychain: → credentialStore:
- DerFluistererApp: ProductionHardwareIdentity + AppSecret.bytes gewired
- KeychainService.swift + KeychainServiceTests.swift entfernt
- Tests-Mocks angepasst

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Manuelle Verifikation (App starten, Key eingeben, Neustart)

**Files:** Keine Änderungen, nur Verifikation.

- [ ] **Step 1: App starten**

Run: `swift run DerFluistererApp`
Expected: App startet als Menüleisten-App. Menu-Bar-Icon erscheint.

- [ ] **Step 2: API-Key in Settings eintragen**

Settings-Fenster öffnen (Cmd+, oder Menü). API-Key eintragen (Wert: ein gültiger sk-ant-… Key).

- [ ] **Step 3: Datei im Filesystem prüfen**

Run: `ls -la "$HOME/Library/Application Support/DerFluisterer/credentials/"`
Expected: Datei `anthropic-api-key.enc` existiert, ~80 Byte, `rw-------` (600).

Run: `file "$HOME/Library/Application Support/DerFluisterer/credentials/anthropic-api-key.enc"`
Expected: `data` (binäres Format, keine erkennbare Struktur).

- [ ] **Step 4: Datei-Inhalt grob sichten (kein Klartext-Key)**

Run: `hexdump -C "$HOME/Library/Application Support/DerFluisterer/credentials/anthropic-api-key.enc" | head`
Expected: Zufällig aussehende Bytes. **Keine** Zeichenfolge `sk-ant-…` erkennbar.

- [ ] **Step 5: App beenden**

Im Menü "Beenden" klicken oder `Cmd+Q` aus Settings-Fenster.

- [ ] **Step 6: App erneut starten**

Run: `swift run DerFluistererApp`
Expected: App startet, Key ist weiterhin eingespeichert (in Settings sichtbar oder durch ersten Korrektur-Test prüfbar).

- [ ] **Step 7: Optional — Diktat-Test**

Hotkey halten, sprechen, loslassen. Korrektur landet im Editor. → API-Key wird vom EncryptedCredentialStore korrekt ausgelesen.

- [ ] **Step 8: App beenden**

- [ ] **Step 9: Alte Keychain-Einträge löschen (Aufräumen)**

Da Migration bewusst nicht implementiert wurde (User tippt neu ein): alten Keychain-Eintrag manuell entfernen:

Run: `security delete-generic-password -s "com.derfluisterer" -a "anthropic-api-key" 2>&1 || echo "(keine Altdaten)"`
Expected: `password has been deleted.` oder `(keine Altdaten)`.

---

## Task 11: Dokumentation

**Files:**
- Create: `docs/build-secret.md`
- Create: `docs/security.md`
- Modify: `README.md`

- [ ] **Step 1: `docs/build-secret.md` schreiben**

Datei: `docs/build-secret.md`:

```markdown
# Build-Time App-Secret

Dieses Dokument richtet sich an Mitwirkende und an den Projekt-Maintainer.

## Zweck

Das App-Secret ist ein zufälliges 32-Byte-Wert, das beim Build in das Binary einkompiliert wird. Es fließt zusammen mit `IOPlatformUUID` und `NSUserName()` in die HKDF-Key-Derivation der verschlüsselten Credentials-Datei ein (`~/Library/Application Support/DerFluisterer/credentials/<account>.enc`).

Genaue Funktionsweise und Bedrohungsmodell: siehe [security.md](security.md).

## Speicherort

- **Pfad:** `Sources/DerFluistererApp/AppSecret.swift`
- **Gitignore-Status:** ignoriert (siehe `.gitignore`)
- **Format:** Swift-Datei mit einem `enum AppSecret { static let bytes: Data = ... }`

## Erstmalige Generierung

Beim ersten Klonen des Repositories existiert `AppSecret.swift` nicht. Der Build schlägt dann mit einem Linker-Fehler `undefined symbol AppSecret` fehl.

Erzeugen via:

```bash
./Scripts/generate-app-secret.sh
```

Das Script legt die Datei genau einmal an. Ein zweiter Aufruf scheitert bewusst hart, um stille Secret-Rotation zu verhindern.

## Sichern

Der Maintainer (Release-Pipeline) MUSS das Secret sichern, z. B. als separaten Eintrag im Passwortmanager. Alternativ: verschlüsseltes Off-Site-Backup der Datei.

Warum: Bei Verlust des Secrets können alle bestehenden Release-Nutzer ihre verschlüsselten Credentials-Dateien nicht mehr entschlüsseln — sie müssen ihren API-Key neu eingeben. Für einzelne Entwickler-Builds ist das unkritisch, für offizielle Releases ist es Breaking.

## Secret rotieren (Notfall)

Nur im echten Kompromittierungsfall. Folgen:

1. `rm Sources/DerFluistererApp/AppSecret.swift`
2. `./Scripts/generate-app-secret.sh`
3. Neues Release bauen.
4. Release-Notes: "Alle Nutzer müssen ihren API-Key neu eintragen."

## Fork-Workflow

Wer einen Fork baut, führt `./Scripts/generate-app-secret.sh` einmal aus. Das erzeugt ein eigenes, vom offiziellen Release unabhängiges Secret. Dateien offizieller Release-Nutzer können damit nicht entschlüsselt werden — das ist gewollt.

## Was NIEMALS tun

- Secret als Compiler-Flag (`-D APP_SECRET=...`) übergeben — landet in Build-Logs, CI-Outputs, Xcode-Build-Settings-Dumps.
- Secret in ein öffentliches CI-Secret-Store eines Public-Repos legen und `set -x` im Script aktivieren.
- `AppSecret.swift` ins Git pushen (erzwungen durch `.gitignore`).
- In `print` / `NSLog` / Fehlermeldungen ausgeben.
```

- [ ] **Step 2: `docs/security.md` schreiben**

Datei: `docs/security.md`:

```markdown
# Security-Architektur: API-Key-Speicherung

## Überblick

Der Anthropic-API-Key wird als AES-GCM-verschlüsselte Datei im Application-Support-Verzeichnis des Nutzers abgelegt. Der Verschlüsselungs-Schlüssel wird zur Laufzeit aus drei Quellen abgeleitet:

1. `IOPlatformUUID` (stabile Geräte-ID)
2. `NSUserName()` (macOS-User-Account-Name)
3. App-Secret (ins Binary einkompilierter 32-Byte-Zufallswert)

Kein dieser Inputs wird in der Credentials-Datei selbst gespeichert.

## Threat-Modell

### Wovor wir schützen

| Szenario | Schutz? | Warum |
|---|---|---|
| Ungezielte Stealer-Malware scannt Home-Verzeichnis nach Klartext-Pattern (`sk-ant-...`) | ✓ | Datei enthält nur Ciphertext, keine Muster |
| Time-Machine-Backup-Festplatte gestohlen | ✓ | Key ist an IOPlatformUUID des Quellgeräts gebunden |
| App-Support-Ordner auf anderen Mac kopiert | ✓ | Gleicher Grund — UUID des Zielgeräts ist anders |
| Datei mitgepatched in Git-Repo (Unfall) | ✓ | Gegen Standalone-Datei: Angreifer kennt weder UUID noch App-Secret |

### Wovor wir NICHT schützen

| Szenario | Kein Schutz | Warum |
|---|---|---|
| Angreifer hat vollen Zugriff auf das laufende/eingeschaltete Gerät | ✗ | Kann UUID, Username, Binary und Datei gleichzeitig lesen — kein Verfahren, das ohne Nutzer-Interaktion entschlüsselt, kann das abwehren |
| Gezielte Reverse-Engineering-Angriffe | ✗ | App-Secret ist im Binary via `strings` extrahierbar; Source-Code ist öffentlich |
| Keylogger, Memory-Dump zur Laufzeit | ✗ | Entschlüsselter Key liegt während der App-Laufzeit im RAM |

## Verfahrensdetails

### Dateiformat

```
[32 Byte Salt][AES.GCM.SealedBox.combined]
```

`SealedBox.combined` = `[12 Byte Nonce][Ciphertext][16 Byte GCM-Tag]`

Keine Magic-Bytes, keine Version-Header → Datei sieht wie reiner Zufall aus.

### Key-Derivation (HKDF-SHA256)

```
ikm  = UTF8(IOPlatformUUID) || 0x00 || UTF8(NSUserName()) || 0x00 || AppSecret
salt = 32 Byte random pro Schreibvorgang
info = UTF8(accountName)  // z. B. "anthropic-api-key"
key  = HKDF<SHA256>(ikm, salt, info, 32 Byte)
```

Der `0x00`-Separator zwischen den String-Inputs verhindert Ambiguität (z. B. UUID="AB", User="CD" vs. UUID="ABCD", User="" würden ohne Separator denselben IKM ergeben).

### Warum HKDF, nicht PBKDF2/scrypt/Argon2?

HKDF ist die richtige Wahl für **High-Entropy-Inputs**:

| Input | Effektive Entropie |
|---|---|
| IOPlatformUUID | ~122 Bit (UUIDv4) |
| NSUserName() | niedrig, aber irrelevant neben den anderen |
| AppSecret | 256 Bit |

Kombinierte Entropie ≥256 Bit → der Derivation-Key ist bereits brute-force-resistent ohne künstliche Rechenkosten. PBKDF2/Argon2 wären passend bei User-gewählten Passwörtern (niedrige Entropie), die durch slow hashing aufgewertet werden müssen. Unsere Inputs brauchen das nicht.

### Warum kein System-Keychain?

Der macOS-System-Keychain hätte eine konzeptuell saubere Lösung (Secure Enclave + TouchID-Gate) geboten, setzt aber eine stabile Code-Signatur-Identität voraus (Designated Requirement über Apple Developer ID). Ohne Apple Developer Program:

- Keychain-ACL wird bei jedem unsignierten App-Update invalidiert → User-Dialog `„möchte auf Schlüsselbund zugreifen"` mit System-Admin-Passwort-Eingabe bei jedem App-Start.
- UX-Wortlaut suggeriert „Zugriff auf alle Passwörter" → untragbar für Endnutzer.

## Akzeptierte Trade-offs

- **App-Secret liegt im Binary** → via `strings` extrahierbar. Das ist bewusst in Kauf genommen — die Hürde für gezielte Angreifer ist damit niedrig. Der Schutz wirkt primär gegen ungezielte Stealer-Malware, die nicht jedes Binary nach Secrets durchsucht.
- **Kein User-Prompt, keine Biometrie** → Bequemlichkeit hat hier Vorrang, da Biometrie ohne Secure Enclave in unsigniertem Kontext Security-Theater wäre.
- **Kein Migration-Pfad vom alten Keychain** → Bestandsnutzer müssen ihren API-Key einmal neu eintragen. Vertretbar bei aktuell sehr kleiner Nutzerbasis; sauberer Bruch ohne Legacy-Code.

## Vergleich mit anderen Tools

**Claude Code CLI** (offizielle Anthropic-Lösung): nutzt für Pay-per-Use-API-Keys die Environment-Variable `ANTHROPIC_API_KEY`, die typischerweise in `.zshrc` (Klartext) liegt. Unsere Lösung bietet in diesem Szenario (unsigniert, ohne Developer Program) echten Schutzgewinn gegenüber Anthropics eigenem Default.
```

- [ ] **Step 3: `README.md` erweitern**

In `README.md` einen Abschnitt "Build from source" ergänzen (falls noch nicht vorhanden) oder bestehenden erweitern:

```markdown
## Build from source

Voraussetzungen: Xcode 15+ / Swift 6.2, macOS 26+.

```bash
git clone https://github.com/msandhofer/Fluesterclon.git
cd Fluesterclon
git lfs pull                           # DeepFilterNet-Modell laden
./Scripts/generate-app-secret.sh       # einmalig: App-Secret für API-Key-Verschlüsselung
swift build -c release
```

Details zum App-Secret: siehe [`docs/build-secret.md`](docs/build-secret.md).
Security-Architektur des API-Keys: siehe [`docs/security.md`](docs/security.md).
```

- [ ] **Step 4: Build noch einmal verifizieren**

Run: `swift build`
Expected: grün.

Run: `swift test`
Expected: alle Tests grün.

- [ ] **Step 5: Commit**

```bash
git add docs/build-secret.md docs/security.md README.md
git commit -m "$(cat <<'EOF'
docs(#44): Security-Architektur und Build-Secret dokumentieren

- docs/security.md: Threat-Modell, HKDF-Begründung, akzeptierte Trade-offs, Vergleich Claude Code CLI
- docs/build-secret.md: Operations-Doku (Generierung, Sichern, Rotation, Fork-Workflow)
- README.md: Build-from-source-Abschnitt um generate-app-secret.sh erweitert

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Ticket #44 — Kommentar und Abschluss

**Files:** keine, reine GitHub-Aktionen.

- [ ] **Step 1: Evaluations-Kommentar in #44 posten**

Run:
```bash
gh issue comment 44 --body "$(cat <<'EOF'
## Ergebnis der Evaluation und Umsetzung (2026-04-24)

### Entscheidungsweg

Die im Ticket vorgesehenen Optionen A–E wurden unter der Randbedingung "unsigniert, kein Apple Developer Program" bewertet:

- **E (Keychain beibehalten):** verworfen — Keychain-ACL bindet an stabile Code-Signatur-Identität, fehlt hier. Jedes App-Update triggert den "möchte auf Schlüsselbund zugreifen"-Dialog mit System-Admin-Passwort — untragbare UX.
- **C (Secure Enclave + TouchID):** verworfen — setzt denselben Signing-Anker voraus wie E, plus `kSecUseDataProtectionKeychain` erfordert Application-Identifier-Entitlement aus einem Provisioning-Profile (Apple-Forums-Beleg [#130264](https://developer.apple.com/forums/thread/130264), [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)).
- **D (UI-Prompt beim Start):** verworfen — inakzeptable UX bei Power-User-Workflow.
- **C' (App-eigenes Passwort):** diskutiert, verworfen zugunsten von B — Passwort-Müdigkeit für marginalen Zusatzschutz ggü. ungezielten Stealern.
- **B (Encrypted File mit Device-bound Key):** gewählt, erweitert um App-Secret.

### Finale Lösung

AES-GCM-verschlüsselte Datei unter `~/Library/Application Support/DerFluisterer/credentials/<account>.enc`, Schlüssel via HKDF-SHA256 aus:

- `IOPlatformUUID` (Gerätebindung)
- `NSUserName()` (Account-Bindung, niedrige Entropie, aber kostenlos)
- Build-Time-injiziertes App-Secret (gitignored in `Sources/DerFluistererApp/AppSecret.swift`)

Pro Schreibvorgang random Salt (32 Byte) → identische Inputs ergeben unterschiedliche Ciphertexte.

### Bedrohungsmodell

**Wirksam gegen:** ungezielte Stealer-Malware (Pattern-Match auf Klartext-Keys), Time-Machine-Backup-Klau, App-Support-Ordner-Kopie auf fremden Mac.

**Nicht wirksam gegen:** Angreifer mit Gerätezugang (fundamental nicht lösbar ohne User-Interaktion), gezielte Reverse-Engineering-Angriffe (App-Secret via `strings` extrahierbar).

Vollständige Doku: [`docs/security.md`](../blob/main/docs/security.md).

### Transparenz

Nach Kerckhoffs'schem Prinzip und dem Open-Source-Standard (Signal, age, 1Password) ist die Security-Architektur bewusst öffentlich dokumentiert — nur das App-Secret ist geheim, der Rest ist Methodik.

### Abweichung vom Ticket-Text

Der Ticket-Text bewertete Option B als "Security-Theater". Diese Einschätzung wurde revidiert: gegen das realistische Bedrohungsmodell (ungezielte Stealer-Malware, der häufigste Angriffsvektor auf API-Keys in freier Wildbahn) wirkt die Verschlüsselung. Theater wäre sie nur bei gezielten Angreifern mit Source-Zugriff — unrealistisch für Nischen-App.

### Migration

Bewusst **keine** Auto-Migration aus der alten Keychain implementiert. Grund: würde einen letzten Keychain-Prompt auslösen, den wir eigentlich loswerden wollen. Nutzer geben ihren API-Key einmal neu ein. Bei aktuell sehr kleiner Nutzerbasis vertretbar.

### Umsetzung

Commits in diesem Issue:
- Plan: `docs/superpowers/plans/2026-04-24-verschluesselte-api-key-ablage.md`
- Scripts + gitignore: (commit-hash-1)
- EncryptedCredentialStore + Tests: (commit-hash-2)
- Protocol-Umbenennung + Wiring: (commit-hash-3)
- Dokumentation: (commit-hash-4)

### Akzeptanzkriterien

- [x] AES-GCM-Verschlüsselung mit HKDF-SHA256-Key-Derivation
- [x] Key-Material: IOPlatformUUID + NSUserName + App-Secret
- [x] App-Secret via Script, gitignored, NICHT als Compiler-Flag
- [x] 9 Unit-Tests (Roundtrip, Persistenz, Device-/User-/Secret-Mismatch, NotFound, Overwrite, Delete)
- [x] Manuelle Verifikation: App-Start → Key-Eingabe → App-Restart → Key weiter nutzbar
- [x] Datei `rw-------` (600), binär ohne Klartext-Muster
- [x] `docs/security.md` und `docs/build-secret.md` angelegt
- [x] README um Build-Schritt erweitert
- [x] Alte Keychain-Altlasten entfernt (KeychainService.swift + Tests)
EOF
)"
```

- [ ] **Step 2: Commit-Hashes im Kommentar nachtragen**

Nach dem Posten: Kommentar editieren und die echten Commit-Hashes der Schritte einfügen:

Run: `gh issue view 44 --comments` — Kommentar-ID der letzten Nachricht notieren.

Run (mit echter ID):
```bash
gh api -X PATCH repos/msandhofer/Fluesterclon/issues/comments/<COMMENT_ID> -f body="..."
```

Oder einfacher: vor `gh issue comment` die echten Hashes aus `git log --oneline -5` einsetzen, dann posten.

- [ ] **Step 3: Issue #44 schließen**

Run: `gh issue close 44 --comment "Implementierung abgeschlossen und verifiziert. Siehe vorhergehenden Evaluations-/Umsetzungs-Kommentar."`
Expected: Issue-State auf `closed`.

- [ ] **Step 4: Memory aktualisieren**

Datei: `/Users/msa/.claude/projects/-Users-msa-Library-CloudStorage-OneDrive-SandhoferConsulting-30-Lernen-KI-project-fluesterclon/memory/project_fluesterclon.md`:

Ersetze die Zeile
```
- #44 API-Key-Storage evaluieren (Device-bound Key geplant)
```
durch Entfernung aus der Offene-Issues-Liste und Ergänzung in der "Kürzlich geschlossen"-Liste:
```
- #44 API-Key-Storage: EncryptedCredentialStore (AES-GCM+HKDF, Hardware-gebundener Key, Build-Time App-Secret) (2026-04-24)
```

Offene Issues reduziert sich auf 4 (#1, #46, #47, #48).

---

## Akzeptanzkriterien (Gesamt)

- [ ] Build (`swift build`) grün
- [ ] Tests (`swift test`) grün — alle bestehenden + 9 neue EncryptedCredentialStore-Tests
- [ ] Manuelle Verifikation erfolgreich (App-Start → Key-Eingabe → Restart → Datei im FS → Key wieder nutzbar)
- [ ] Datei `~/Library/Application Support/DerFluisterer/credentials/anthropic-api-key.enc` existiert, `0600`, binär ohne erkennbares Klartext-Muster
- [ ] Alter Keychain-Eintrag entfernt (per `security delete-generic-password`)
- [ ] `AppSecret.swift` liegt NICHT im Git (`git status` sauber, `git log` enthält keine Referenz)
- [ ] `docs/build-secret.md`, `docs/security.md` vorhanden
- [ ] README um Build-Schritt erweitert
- [ ] Ticket #44 mit Evaluations-/Umsetzungs-Kommentar geschlossen
- [ ] Memory `project_fluesterclon.md` aktualisiert
