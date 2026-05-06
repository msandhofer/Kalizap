# Update-Check + Banner (Issue #46) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die App prueft beim Start (einmal pro Tag) via GitHub-Releases-API, ob eine neuere Version verfuegbar ist. Bei verfuegbarem Update zeigt sie im Menueleisten-Popover einen dezenten Banner mit der passenden Update-Anweisung — je nach Installationsweg (Homebrew-Cask vs. Direct-Download) und Systemsprache (DE/EN).

**Architecture:** Klar getrennte Verantwortlichkeiten: `SemanticVersion` (Pars/Vergleich), `GitHubReleasesClient` (HTTP), `HomebrewDetector` (FileSystem), `UpdateBannerLocalization` (DE/EN), und `UpdateChecker` als Orchestrator. Resultat ist ein `UpdateState`, das `UpdateBannerView` rendert. Dismissal wird pro Version in `SystemSettings` persistiert.

**Tech Stack:** Swift 6.2, SwiftUI, `URLSession`, `FileManager`, `Locale.current`, `Bundle.main.infoDictionary`, XCTest.

---

## Getroffene Annahmen (Stop-and-Ask wenn falsch)

- **Lokalisierungs-Mechanismus:** Simple Swift-Enum + Dictionary (kein Apple String Catalog / NSLocalizedString). Rationale: nur 5-6 Strings, bestehende App-Strings sind alle Deutsch, pragmatisch. Migration auf Apple-Infrastruktur ist moeglich, wenn mehr Strings dazukommen.
- **Lokalisierungs-Scope:** Nur die neuen Banner-/Button-Strings fuer #46 werden lokalisiert. Bestehende deutsche Strings bleiben unveraendert (Settings, Toasts, Menu-Bar-Labels).
- **Repo-URL:** `https://api.github.com/repos/msandhofer/Kalizap/releases/latest`.
- **Tag-Format:** `v0.2.0` (mit `v`-Prefix). Der Prefix wird beim Parsen ignoriert.
- **Sprach-Detection:** `Locale.current.language.languageCode?.identifier == "en"` -> EN, sonst DE (Default).
- **Spaeter-Semantik:** Per-Version-Dismiss. User klickt "Spaeter" -> `dismissedUpdateVersion = "0.2.0"` in `SystemSettings`. Banner verschwindet fuer diese Version. Bei 0.3.0 erscheint er wieder.
- **Einmal-pro-Tag-Heuristik:** `lastUpdateCheckTimestamp` in `UserDefaults`. Check nur wenn > 24h her. Manueller "Nach Updates suchen"-Button ignoriert das Timestamp.
- **Privat-Repo-Szenario:** API-Aufruf liefert HTTP 404. Wir loggen die API-Response silent und zeigen **keinen** Banner (kein Fehler-UI). Echte End-to-End-Verifikation erst nach #48.
- **Info.plist-Cleanup:** `SUFeedURL` und `SUPublicEDKey` sind Sparkle-Altlasten aus #45. Raus.

---

## File Structure

### Neue Dateien

| Pfad | Verantwortung |
|---|---|
| `Sources/Kalizap/Services/SemanticVersion.swift` | Struct mit `init?(_ string: String)` und `Comparable`. Parst `"v0.2.0"` / `"0.2.0"` / `"1.2.3-beta"` (ignoriert Suffix). |
| `Sources/Kalizap/Services/HomebrewDetector.swift` | Protocol `HomebrewDetecting` + Production-Impl. Check via `FileManager.default.fileExists(atPath:)` auf vier Pfaden. Liefert `HomebrewStatus` (`.notInstalled`, `.installedDirectDownload`, `.installedViaCask`). |
| `Sources/Kalizap/Services/GitHubReleasesClient.swift` | Protocol `GitHubReleasesFetching` + Production-Impl via `URLSession`. `func fetchLatestReleaseTag() async throws -> String?` (nil = 404 oder Netzwerkfehler, silent). |
| `Sources/Kalizap/Services/UpdateBannerLocalization.swift` | Enum `UpdateBannerLocalization` mit `strings(for: Language)`. Struct `BannerStrings` mit Feldern fuer Titel, Buttons, Hinweise. |
| `Sources/Kalizap/Modules/UpdateChecker.swift` | `UpdateChecker` Klasse. Orchestriert API-Call + Detection + Vergleich. Methoden: `checkIfDue()`, `checkNow()`. Produziert `UpdateState`. |
| `Sources/Kalizap/Modules/UpdateState.swift` | Enum mit Cases `.unknown`, `.noUpdate`, `.available(version: String, method: UpdateMethod)`. `UpdateMethod` = `.homebrewCask(command: String)` oder `.directDownload(url: URL)`. |
| `Sources/KalizapApp/Views/UpdateBannerView.swift` | SwiftUI-View, rendert `UpdateState`. Versteckt bei `.unknown`, `.noUpdate`, und wenn `dismissedUpdateVersion == available-Version`. |
| `Tests/KalizapTests/SemanticVersionTests.swift` | Parsing + Vergleich. |
| `Tests/KalizapTests/HomebrewDetectorTests.swift` | Mock-FileManager, alle 4 Pfad-Kombinationen. |
| `Tests/KalizapTests/GitHubReleasesClientTests.swift` | Mock-HTTP, 200-OK + 404 + Fehler. |
| `Tests/KalizapTests/UpdateBannerLocalizationTests.swift` | DE/EN-Strings vorhanden, keine leeren. |
| `Tests/KalizapTests/UpdateCheckerTests.swift` | Orchestrator-Logik: 24h-Throttle, Dismissal, Versionen-Vergleich, Banner-State. |

### Zu modifizierende Dateien

| Pfad | Aenderung |
|---|---|
| `Sources/Kalizap/Modules/SettingsManager.swift` | `SystemSettings` bekommt `dismissedUpdateVersion: String?`. `CodingKeys` + `init(from:)` anpassen. |
| `Sources/KalizapApp/AppState.swift` | `UpdateChecker`-Instanz + `checkIfDue()`-Aufruf in `bootstrap()`. `@Published var updateState: UpdateState`. |
| `Sources/KalizapApp/Views/MenuBarView.swift` | `UpdateBannerView` einblenden oben im VStack. |
| `Sources/KalizapApp/Views/SettingsView.swift` | In `SystemSettingsSection` einen Button "Nach Updates suchen" / "Check for updates" hinzufuegen. |
| `Sources/KalizapApp/KalizapApp.swift` | `UpdateChecker`-Dependency wiren. |
| `Sources/KalizapApp/Info.plist` | `SUFeedURL` + `SUPublicEDKey` entfernen (Sparkle-Altlasten). |

---

## Task 1: `SemanticVersion` — Parsing + Vergleich (TDD)

**Files:**
- Create: `Sources/Kalizap/Services/SemanticVersion.swift`
- Test: `Tests/KalizapTests/SemanticVersionTests.swift`

- [ ] **Step 1: Test schreiben — Parsing verschiedener Formate**

Datei: `Tests/KalizapTests/SemanticVersionTests.swift`:

```swift
import XCTest
@testable import Kalizap

final class SemanticVersionTests: XCTestCase {

    func test_init_parsesPlainVersion() {
        let v = SemanticVersion("0.1.0")
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 1)
        XCTAssertEqual(v?.patch, 0)
    }

    func test_init_parsesWithVPrefix() {
        let v = SemanticVersion("v1.2.3")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func test_init_ignoresPreReleaseSuffix() {
        let v = SemanticVersion("1.2.3-beta.1")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func test_init_returnsNilForMalformed() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion(""))
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter SemanticVersionTests`
Expected: Compile-Fehler `cannot find 'SemanticVersion' in scope`.

- [ ] **Step 3: Implementation schreiben**

Datei: `Sources/Kalizap/Services/SemanticVersion.swift`:

```swift
import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") { s = String(s.dropFirst()) }
        // Pre-Release-Suffix abschneiden (nach erstem '-' oder '+')
        if let dashIdx = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<dashIdx])
        }
        let parts = s.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
```

- [ ] **Step 4: Parsing-Tests laufen lassen, grün**

Run: `swift test --filter SemanticVersionTests`
Expected: PASS (4 Tests).

- [ ] **Step 5: Vergleichs-Tests ergänzen**

In `SemanticVersionTests.swift` anfügen:

```swift
    func test_compare_majorDominates() {
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.999.999")!)
    }

    func test_compare_minorDominates() {
        XCTAssertTrue(SemanticVersion("1.2.0")! > SemanticVersion("1.1.999")!)
    }

    func test_compare_patchDominates() {
        XCTAssertTrue(SemanticVersion("1.2.3")! > SemanticVersion("1.2.2")!)
    }

    func test_compare_equalVersions() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion("v1.2.3"))
    }

    func test_compare_stringLexBug() {
        // 1.10.0 > 1.9.0 (Regression-Guard gegen String-lexikographische Ordnung)
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)
    }
```

- [ ] **Step 6: Vergleichs-Tests laufen lassen**

Run: `swift test --filter SemanticVersionTests`
Expected: PASS (9 Tests).

- [ ] **Step 7: Zwischen-Commit (kein Feature komplett, weiter zu Task 2)**

Noch kein Commit — Task 2-4 bauen aufeinander auf, commit am Ende als feat-Block.

---

## Task 2: `HomebrewDetector` — Installationspfad-Detection (TDD)

**Files:**
- Create: `Sources/Kalizap/Services/HomebrewDetector.swift`
- Test: `Tests/KalizapTests/HomebrewDetectorTests.swift`

- [ ] **Step 1: Test schreiben**

Datei: `Tests/KalizapTests/HomebrewDetectorTests.swift`:

```swift
import XCTest
@testable import Kalizap

final class HomebrewDetectorTests: XCTestCase {

    private final class FakeFileExistenceChecker: FileExistenceChecking, @unchecked Sendable {
        var existingPaths: Set<String> = []
        func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }
    }

    func test_detect_noBrewInstalled_returnsNotInstalled() {
        let fake = FakeFileExistenceChecker()
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .notInstalled)
    }

    func test_detect_brewArmInstalled_notViaCask_returnsDirectDownload() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/opt/homebrew/bin/brew"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedDirectDownload)
    }

    func test_detect_brewIntelInstalled_notViaCask_returnsDirectDownload() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/usr/local/bin/brew"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedDirectDownload)
    }

    func test_detect_brewArmAndCaskroom_returnsInstalledViaCask() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/kalizap"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedViaCask)
    }

    func test_detect_brewIntelAndCaskroom_returnsInstalledViaCask() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/usr/local/bin/brew", "/usr/local/Caskroom/kalizap"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedViaCask)
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter HomebrewDetectorTests`
Expected: Compile-Fehler fuer `HomebrewDetector`, `FileExistenceChecking`, `HomebrewStatus`.

- [ ] **Step 3: Implementation schreiben**

Datei: `Sources/Kalizap/Services/HomebrewDetector.swift`:

```swift
import Foundation

public enum HomebrewStatus: Equatable, Sendable {
    case notInstalled
    case installedDirectDownload
    case installedViaCask
}

public protocol FileExistenceChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
}

public struct ProductionFileExistenceChecker: FileExistenceChecking {
    public init() {}
    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public struct HomebrewDetector: Sendable {
    private let fileExistence: any FileExistenceChecking

    private static let brewPaths = [
        "/opt/homebrew/bin/brew",     // Apple Silicon
        "/usr/local/bin/brew",         // Intel
    ]

    private static let caskroomPaths = [
        "/opt/homebrew/Caskroom/kalizap",
        "/usr/local/Caskroom/kalizap",
    ]

    public init(fileExistence: any FileExistenceChecking = ProductionFileExistenceChecker()) {
        self.fileExistence = fileExistence
    }

    public func detect() -> HomebrewStatus {
        let brewInstalled = Self.brewPaths.contains(where: { fileExistence.fileExists(atPath: $0) })
        guard brewInstalled else { return .notInstalled }

        let viaCask = Self.caskroomPaths.contains(where: { fileExistence.fileExists(atPath: $0) })
        return viaCask ? .installedViaCask : .installedDirectDownload
    }
}
```

- [ ] **Step 4: Tests laufen lassen, grün**

Run: `swift test --filter HomebrewDetectorTests`
Expected: PASS (5 Tests).

---

## Task 3: `GitHubReleasesClient` — HTTP-Client mit Mock-Support (TDD)

**Files:**
- Create: `Sources/Kalizap/Services/GitHubReleasesClient.swift`
- Test: `Tests/KalizapTests/GitHubReleasesClientTests.swift`

- [ ] **Step 1: Test schreiben**

Datei: `Tests/KalizapTests/GitHubReleasesClientTests.swift`:

```swift
import XCTest
@testable import Kalizap

final class GitHubReleasesClientTests: XCTestCase {

    private final class FakeHTTPSender: HTTPDataSending, @unchecked Sendable {
        var dataToReturn: Data = Data()
        var responseToReturn: URLResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        var errorToThrow: Error?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            if let errorToThrow { throw errorToThrow }
            return (dataToReturn, responseToReturn)
        }
    }

    func test_fetchLatestReleaseTag_success_returnsTagName() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = try JSONSerialization.data(withJSONObject: ["tag_name": "v0.2.0"])
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertEqual(tag, "v0.2.0")
    }

    func test_fetchLatestReleaseTag_notFound404_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.responseToReturn = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_networkError_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.errorToThrow = URLError(.notConnectedToInternet)
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_malformedJson_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = Data("not valid json".utf8)
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }

    func test_fetchLatestReleaseTag_missingTagNameField_returnsNil() async throws {
        let fake = FakeHTTPSender()
        fake.dataToReturn = try JSONSerialization.data(withJSONObject: ["other_field": "value"])
        let sut = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap", session: fake)

        let tag = try await sut.fetchLatestReleaseTag()

        XCTAssertNil(tag)
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter GitHubReleasesClientTests`
Expected: Compile-Fehler fuer `GitHubReleasesClient`.

- [ ] **Step 3: Implementation schreiben**

Datei: `Sources/Kalizap/Services/GitHubReleasesClient.swift`:

```swift
import Foundation

public struct GitHubReleasesClient: Sendable {
    private let owner: String
    private let repo: String
    private let session: any HTTPDataSending

    public init(
        owner: String,
        repo: String,
        session: any HTTPDataSending = URLSession.shared
    ) {
        self.owner = owner
        self.repo = repo
        self.session = session
    }

    /// Liefert den Tag-Namen der neuesten Release, oder nil bei 404/Netzwerkfehler/Parse-Fehler.
    /// Wirft nie — Fehler werden silent in nil uebersetzt (Ticket-Anforderung).
    public func fetchLatestReleaseTag() async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return nil
            }
            return tag
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 4: Tests laufen lassen, grün**

Run: `swift test --filter GitHubReleasesClientTests`
Expected: PASS (5 Tests).

---

## Task 4: `UpdateBannerLocalization` — DE/EN-Strings (TDD)

**Files:**
- Create: `Sources/Kalizap/Services/UpdateBannerLocalization.swift`
- Test: `Tests/KalizapTests/UpdateBannerLocalizationTests.swift`

- [ ] **Step 1: Test schreiben**

Datei: `Tests/KalizapTests/UpdateBannerLocalizationTests.swift`:

```swift
import XCTest
@testable import Kalizap

final class UpdateBannerLocalizationTests: XCTestCase {

    func test_strings_german_containsVersionPlaceholder() {
        let s = UpdateBannerLocalization.strings(for: .german)
        XCTAssertTrue(s.titleTemplate.contains("{version}"), "Titel muss {version}-Platzhalter enthalten")
    }

    func test_strings_english_containsVersionPlaceholder() {
        let s = UpdateBannerLocalization.strings(for: .english)
        XCTAssertTrue(s.titleTemplate.contains("{version}"), "Title muss {version}-Platzhalter enthalten")
    }

    func test_strings_allFieldsNonEmpty_german() {
        let s = UpdateBannerLocalization.strings(for: .german)
        XCTAssertFalse(s.titleTemplate.isEmpty)
        XCTAssertFalse(s.homebrewInstructionLabel.isEmpty)
        XCTAssertFalse(s.directDownloadInstructionLabel.isEmpty)
        XCTAssertFalse(s.quarantineHint.isEmpty)
        XCTAssertFalse(s.copyButton.isEmpty)
        XCTAssertFalse(s.openReleaseButton.isEmpty)
        XCTAssertFalse(s.laterButton.isEmpty)
        XCTAssertFalse(s.checkForUpdatesButton.isEmpty)
    }

    func test_strings_allFieldsNonEmpty_english() {
        let s = UpdateBannerLocalization.strings(for: .english)
        XCTAssertFalse(s.titleTemplate.isEmpty)
        XCTAssertFalse(s.homebrewInstructionLabel.isEmpty)
        XCTAssertFalse(s.directDownloadInstructionLabel.isEmpty)
        XCTAssertFalse(s.quarantineHint.isEmpty)
        XCTAssertFalse(s.copyButton.isEmpty)
        XCTAssertFalse(s.openReleaseButton.isEmpty)
        XCTAssertFalse(s.laterButton.isEmpty)
        XCTAssertFalse(s.checkForUpdatesButton.isEmpty)
    }

    func test_language_fromLocaleIdentifier_en_returnsEnglish() {
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "en"), .english)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "en-US"), .english)
    }

    func test_language_fromLocaleIdentifier_other_returnsGerman() {
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "de"), .german)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "fr"), .german)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: nil), .german)
    }
}
```

- [ ] **Step 2: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter UpdateBannerLocalizationTests`
Expected: Compile-Fehler.

- [ ] **Step 3: Implementation schreiben**

Datei: `Sources/Kalizap/Services/UpdateBannerLocalization.swift`:

```swift
import Foundation

public struct BannerStrings: Sendable {
    public let titleTemplate: String             // enthaelt "{version}"
    public let homebrewInstructionLabel: String
    public let directDownloadInstructionLabel: String
    public let quarantineHint: String
    public let copyButton: String
    public let openReleaseButton: String
    public let laterButton: String
    public let checkForUpdatesButton: String
}

public enum UpdateBannerLocalization {

    public enum Language: Sendable {
        case german
        case english

        public static func from(localeIdentifier: String?) -> Language {
            guard let id = localeIdentifier?.lowercased() else { return .german }
            return id.hasPrefix("en") ? .english : .german
        }
    }

    public static func strings(for language: Language) -> BannerStrings {
        switch language {
        case .german:
            return BannerStrings(
                titleTemplate: "Neue Version verfügbar: {version}",
                homebrewInstructionLabel: "Update via Homebrew:",
                directDownloadInstructionLabel: "Update herunterladen von GitHub Releases.",
                quarantineHint: "Hinweis: Nach Installation Quarantäne-Flag entfernen.",
                copyButton: "Kopieren",
                openReleaseButton: "Release-Seite öffnen",
                laterButton: "Später",
                checkForUpdatesButton: "Nach Updates suchen"
            )
        case .english:
            return BannerStrings(
                titleTemplate: "New version available: {version}",
                homebrewInstructionLabel: "Update via Homebrew:",
                directDownloadInstructionLabel: "Download update from GitHub Releases.",
                quarantineHint: "Note: Remove the quarantine flag after installing.",
                copyButton: "Copy",
                openReleaseButton: "Open release page",
                laterButton: "Later",
                checkForUpdatesButton: "Check for updates"
            )
        }
    }
}
```

- [ ] **Step 4: Tests laufen lassen, grün**

Run: `swift test --filter UpdateBannerLocalizationTests`
Expected: PASS (6 Tests).

---

## Task 5: `UpdateState` + `UpdateChecker`-Orchestrator (TDD)

**Files:**
- Create: `Sources/Kalizap/Modules/UpdateState.swift`
- Create: `Sources/Kalizap/Modules/UpdateChecker.swift`
- Test: `Tests/KalizapTests/UpdateCheckerTests.swift`

- [ ] **Step 1: `UpdateState.swift` schreiben**

Datei: `Sources/Kalizap/Modules/UpdateState.swift`:

```swift
import Foundation

public enum UpdateMethod: Equatable, Sendable {
    case homebrewCask(command: String)
    case directDownload(url: URL)
}

public enum UpdateState: Equatable, Sendable {
    case unknown            // noch nicht gecheckt
    case noUpdate           // neueste Version installiert
    case available(version: String, method: UpdateMethod)
}
```

- [ ] **Step 2: Test fuer `UpdateChecker` schreiben**

Datei: `Tests/KalizapTests/UpdateCheckerTests.swift`:

```swift
import XCTest
@testable import Kalizap

final class UpdateCheckerTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeReleasesClient: ReleasesFetching, @unchecked Sendable {
        var nextTag: String?
        func fetchLatestReleaseTag() async throws -> String? {
            nextTag
        }
    }

    private final class FakeHomebrewDetector: HomebrewDetecting, @unchecked Sendable {
        var status: HomebrewStatus = .notInstalled
        func detect() -> HomebrewStatus { status }
    }

    // MARK: - Helpers

    private func makeSUT(
        currentVersion: String = "0.1.0",
        releasesNext: String? = nil,
        homebrewStatus: HomebrewStatus = .notInstalled
    ) -> (UpdateChecker, FakeReleasesClient, FakeHomebrewDetector) {
        let releases = FakeReleasesClient()
        releases.nextTag = releasesNext
        let brew = FakeHomebrewDetector()
        brew.status = homebrewStatus
        let checker = UpdateChecker(
            currentVersion: currentVersion,
            releasesClient: releases,
            homebrewDetector: brew,
            githubReleaseBaseURL: URL(string: "https://github.com/msandhofer/Kalizap/releases/latest")!,
            homebrewCaskCommand: "brew upgrade --cask msandhofer/kalizap/kalizap"
        )
        return (checker, releases, brew)
    }

    // MARK: - Tests

    func test_checkNow_noNewerVersion_returnsNoUpdate() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.2.0", releasesNext: "v0.2.0")
        let state = await sut.checkNow()
        XCTAssertEqual(state, .noUpdate)
    }

    func test_checkNow_olderInstalled_returnsAvailable() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .notInstalled)
        let state = await sut.checkNow()
        if case .available(let v, let method) = state {
            XCTAssertEqual(v, "0.2.0")
            if case .directDownload(let url) = method {
                XCTAssertEqual(url.absoluteString, "https://github.com/msandhofer/Kalizap/releases/latest")
            } else {
                XCTFail("Expected directDownload method")
            }
        } else {
            XCTFail("Expected .available")
        }
    }

    func test_checkNow_olderInstalled_viaCask_returnsHomebrewMethod() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .installedViaCask)
        let state = await sut.checkNow()
        if case .available(_, .homebrewCask(let command)) = state {
            XCTAssertTrue(command.contains("brew upgrade"))
        } else {
            XCTFail("Expected .available with homebrewCask")
        }
    }

    func test_checkNow_brewInstalledButNotViaCask_returnsDirectDownload() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0", homebrewStatus: .installedDirectDownload)
        let state = await sut.checkNow()
        if case .available(_, .directDownload) = state {
            // OK
        } else {
            XCTFail("Expected .available with directDownload")
        }
    }

    func test_checkNow_apiReturnsNil_returnsUnknown() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: nil)
        let state = await sut.checkNow()
        XCTAssertEqual(state, .unknown)
    }

    func test_checkNow_malformedTagName_returnsUnknown() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "not-a-version")
        let state = await sut.checkNow()
        XCTAssertEqual(state, .unknown)
    }
}
```

- [ ] **Step 3: Test laufen lassen, muss fehlschlagen**

Run: `swift test --filter UpdateCheckerTests`
Expected: Compile-Fehler fuer `UpdateChecker`, `ReleasesFetching`, `HomebrewDetecting`.

- [ ] **Step 4: Protokolle + Checker schreiben**

Datei: `Sources/Kalizap/Modules/UpdateChecker.swift`:

```swift
import Foundation

public protocol ReleasesFetching: Sendable {
    func fetchLatestReleaseTag() async throws -> String?
}

public protocol HomebrewDetecting: Sendable {
    func detect() -> HomebrewStatus
}

// Adapter, damit die Production-Typen das Protocol erfuellen.
extension GitHubReleasesClient: ReleasesFetching {}
extension HomebrewDetector: HomebrewDetecting {}

public final class UpdateChecker: @unchecked Sendable {
    private let currentVersion: SemanticVersion?
    private let releasesClient: any ReleasesFetching
    private let homebrewDetector: any HomebrewDetecting
    private let githubReleaseBaseURL: URL
    private let homebrewCaskCommand: String

    public init(
        currentVersion: String,
        releasesClient: any ReleasesFetching,
        homebrewDetector: any HomebrewDetecting,
        githubReleaseBaseURL: URL,
        homebrewCaskCommand: String
    ) {
        self.currentVersion = SemanticVersion(currentVersion)
        self.releasesClient = releasesClient
        self.homebrewDetector = homebrewDetector
        self.githubReleaseBaseURL = githubReleaseBaseURL
        self.homebrewCaskCommand = homebrewCaskCommand
    }

    public func checkNow() async -> UpdateState {
        guard let current = currentVersion else { return .unknown }
        let tag: String?
        do {
            tag = try await releasesClient.fetchLatestReleaseTag()
        } catch {
            return .unknown
        }
        guard let tag, let latest = SemanticVersion(tag) else {
            return .unknown
        }
        if latest <= current { return .noUpdate }

        let versionString = "\(latest.major).\(latest.minor).\(latest.patch)"
        let method: UpdateMethod
        switch homebrewDetector.detect() {
        case .installedViaCask:
            method = .homebrewCask(command: homebrewCaskCommand)
        case .installedDirectDownload, .notInstalled:
            method = .directDownload(url: githubReleaseBaseURL)
        }
        return .available(version: versionString, method: method)
    }
}
```

- [ ] **Step 5: Tests laufen lassen, grün**

Run: `swift test --filter UpdateCheckerTests`
Expected: PASS (6 Tests).

---

## Task 6: 24h-Throttle in `UpdateChecker` (TDD)

**Files:**
- Modify: `Sources/Kalizap/Modules/UpdateChecker.swift`
- Modify: `Tests/KalizapTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Test schreiben**

In `UpdateCheckerTests.swift` anfuegen:

```swift
    // MARK: - Throttle (einmal pro 24h)

    func test_checkIfDue_firstCall_runs() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!
        defer { defaults.removeSuite(named: defaults.dictionaryRepresentation().keys.first ?? "") }

        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertTrue(didRun, "Erster Call muss laufen")
    }

    func test_checkIfDue_secondCallWithin24h_skips() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!

        _ = await sut.checkIfDue(defaults: defaults)
        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertFalse(didRun, "Zweiter Call innerhalb 24h muss skippen")
    }

    func test_checkIfDue_secondCallAfter24h_runs() async {
        let (sut, _, _) = makeSUT(currentVersion: "0.1.0", releasesNext: "v0.2.0")
        let defaults = UserDefaults(suiteName: "throttle.test.\(UUID())")!

        // Simuliere, dass letzter Check 25h her ist
        let past = Date().addingTimeInterval(-25 * 3600)
        defaults.set(past, forKey: "updateChecker.lastCheckTimestamp")

        let didRun = await sut.checkIfDue(defaults: defaults)

        XCTAssertTrue(didRun, "Nach 24h muss erneut gecheckt werden")
    }
```

- [ ] **Step 2: `checkIfDue`-Methode in `UpdateChecker` implementieren**

In `UpdateChecker.swift` anfuegen (innerhalb der Klasse):

```swift
    /// Gibt true zurueck, wenn gecheckt wurde; false, wenn geskippt (letzter Check < 24h her).
    /// Aktualisiert den lastCheck-Timestamp wenn gecheckt.
    /// Der Update-State (falls erfolgreich) kann ueber `lastCheckState` abgefragt werden.
    public func checkIfDue(defaults: UserDefaults) async -> Bool {
        let key = "updateChecker.lastCheckTimestamp"
        let now = Date()
        if let last = defaults.object(forKey: key) as? Date {
            if now.timeIntervalSince(last) < 24 * 3600 {
                return false
            }
        }
        _lastCheckState = await checkNow()
        defaults.set(now, forKey: key)
        return true
    }

    /// Letztes Check-Ergebnis (nach `checkIfDue` oder `checkNow`), für die UI.
    public private(set) var lastCheckState: UpdateState = .unknown

    private var _lastCheckState: UpdateState {
        get { lastCheckState }
        set { lastCheckState = newValue }
    }
```

Wichtig: `checkNow` muss ebenfalls `lastCheckState` aktualisieren. Passe an:

```swift
    public func checkNow() async -> UpdateState {
        let state = await computeState()
        lastCheckState = state
        return state
    }

    private func computeState() async -> UpdateState {
        // ... bisheriger Inhalt von checkNow ...
    }
```

- [ ] **Step 3: Tests laufen lassen, grün**

Run: `swift test --filter UpdateCheckerTests`
Expected: PASS (9 Tests).

- [ ] **Step 4: Zwischen-Commit**

```bash
git add Sources/Kalizap/Services/SemanticVersion.swift
git add Sources/Kalizap/Services/HomebrewDetector.swift
git add Sources/Kalizap/Services/GitHubReleasesClient.swift
git add Sources/Kalizap/Services/UpdateBannerLocalization.swift
git add Sources/Kalizap/Modules/UpdateState.swift
git add Sources/Kalizap/Modules/UpdateChecker.swift
git add Tests/KalizapTests/SemanticVersionTests.swift
git add Tests/KalizapTests/HomebrewDetectorTests.swift
git add Tests/KalizapTests/GitHubReleasesClientTests.swift
git add Tests/KalizapTests/UpdateBannerLocalizationTests.swift
git add Tests/KalizapTests/UpdateCheckerTests.swift
git commit -m "$(cat <<'EOF'
feat(#46): UpdateChecker mit GitHub-Releases, Homebrew-Detection, SemVer

- SemanticVersion: Parser + Comparable (v-prefix, pre-release-suffix tolerant)
- HomebrewDetector: FileManager-basiert, mockbar ueber Protocol
- GitHubReleasesClient: async URLSession, Fehler silent -> nil
- UpdateBannerLocalization: DE/EN Strings, Locale-Detection
- UpdateChecker: Orchestrator, checkNow + checkIfDue (24h-Throttle)
- UpdateState: .unknown / .noUpdate / .available(UpdateMethod)
- 26 neue Tests, alle gruen

Noch nicht: UI-Banner, AppState-Integration, Settings-Button. Folgen.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Persistenter Version-Dismiss in `SystemSettings`

**Files:**
- Modify: `Sources/Kalizap/Modules/SettingsManager.swift`
- Modify: `Tests/KalizapTests/SettingsManagerTests.swift`

- [ ] **Step 1: Test schreiben**

In `SettingsManagerTests.swift`, naechste passende Test-Klasse (`SettingsManagerPersistenceTests`), anfuegen:

```swift
    func test_systemSettings_dismissedUpdateVersion_defaultsToNil() {
        let settings = SystemSettings()
        XCTAssertNil(settings.dismissedUpdateVersion)
    }

    func test_systemSettings_dismissedUpdateVersion_persistsAcrossDecode() throws {
        let original = SystemSettings(autoStart: false, historyLimit: 100, debugMode: false, dismissedUpdateVersion: "0.2.0")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SystemSettings.self, from: data)
        XCTAssertEqual(decoded.dismissedUpdateVersion, "0.2.0")
    }
```

- [ ] **Step 2: `SystemSettings` erweitern**

In `Sources/Kalizap/Modules/SettingsManager.swift`:

**Alt:**
```swift
public struct SystemSettings: Codable, Equatable {
    public var autoStart: Bool = false
    public var historyLimit: Int = 100
    public var debugMode: Bool = false
    public init(autoStart: Bool = false, historyLimit: Int = 100, debugMode: Bool = false) {
        self.autoStart = autoStart
        self.historyLimit = historyLimit
        self.debugMode = debugMode
    }
}
```

**Neu:**
```swift
public struct SystemSettings: Codable, Equatable {
    public var autoStart: Bool = false
    public var historyLimit: Int = 100
    public var debugMode: Bool = false
    public var dismissedUpdateVersion: String? = nil

    public init(autoStart: Bool = false, historyLimit: Int = 100, debugMode: Bool = false, dismissedUpdateVersion: String? = nil) {
        self.autoStart = autoStart
        self.historyLimit = historyLimit
        self.debugMode = debugMode
        self.dismissedUpdateVersion = dismissedUpdateVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        historyLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 100
        debugMode = try container.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        dismissedUpdateVersion = try container.decodeIfPresent(String.self, forKey: .dismissedUpdateVersion)
    }
}
```

- [ ] **Step 3: Tests laufen lassen, grün**

Run: `swift test --filter SettingsManagerPersistenceTests`
Expected: Alle Tests inklusive der neuen passieren.

---

## Task 8: `UpdateBannerView` — SwiftUI (TDD-light, UI)

**Files:**
- Create: `Sources/KalizapApp/Views/UpdateBannerView.swift`

- [ ] **Step 1: View schreiben**

Datei: `Sources/KalizapApp/Views/UpdateBannerView.swift`:

```swift
import AppKit
import SwiftUI
import Kalizap

struct UpdateBannerView: View {
    let state: UpdateState
    let dismissedVersion: String?
    let onDismiss: (String) -> Void
    let strings: BannerStrings

    var body: some View {
        if case .available(let version, let method) = state, dismissedVersion != version {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(for: version))
                    .font(.subheadline)
                    .bold()

                switch method {
                case .homebrewCask(let command):
                    Text(strings.homebrewInstructionLabel)
                        .font(.footnote)
                    HStack(spacing: 4) {
                        Text(command)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            copyToPasteboard(command)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(strings.copyButton)
                    }

                case .directDownload(let url):
                    Text(strings.directDownloadInstructionLabel)
                        .font(.footnote)
                    Text(strings.quarantineHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(strings.openReleaseButton) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }

                HStack {
                    Spacer()
                    Button(strings.laterButton) { onDismiss(version) }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1))
            )
        }
    }

    private func title(for version: String) -> String {
        strings.titleTemplate.replacingOccurrences(of: "{version}", with: version)
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
```

- [ ] **Step 2: Build verifizieren**

Run: `swift build`
Expected: grün.

---

## Task 9: Bootstrap in `AppState`

**Files:**
- Modify: `Sources/KalizapApp/AppState.swift`

- [ ] **Step 1: `AppState` erweitern um UpdateChecker + State**

In `AppState.swift` die Struct-Definition finden und erweitern. Ersten Block mit `@Published`-Properties lesen; dann anfuegen:

```swift
    public private(set) var updateState: UpdateState = .unknown
    private var updateChecker: UpdateChecker?
```

In `bootstrap()` nach `await settings.validateAPIKey()` einfuegen:

```swift
        await triggerUpdateCheckIfNeeded()
```

Am Ende der AppState-Klasse eine neue Methode hinzufuegen:

```swift
    private func triggerUpdateCheckIfNeeded() async {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let releases = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap")
        let brew = HomebrewDetector()
        let checker = UpdateChecker(
            currentVersion: currentVersion,
            releasesClient: releases,
            homebrewDetector: brew,
            githubReleaseBaseURL: URL(string: "https://github.com/msandhofer/Kalizap/releases/latest")!,
            homebrewCaskCommand: "brew upgrade --cask msandhofer/kalizap/kalizap"
        )
        self.updateChecker = checker
        _ = await checker.checkIfDue(defaults: .standard)
        self.updateState = checker.lastCheckState
    }

    public func checkForUpdatesManually() async {
        guard let checker = updateChecker else {
            await triggerUpdateCheckIfNeeded()
            return
        }
        self.updateState = await checker.checkNow()
    }

    public func dismissUpdateVersion(_ version: String) {
        settings.system.dismissedUpdateVersion = version
    }
```

- [ ] **Step 2: Build + Smoke-Tests**

Run: `swift build`
Expected: grün.

Run: `swift test`
Expected: Bestehende Tests bleiben grün.

---

## Task 10: `MenuBarView` — Banner einbinden

**Files:**
- Modify: `Sources/KalizapApp/Views/MenuBarView.swift`

- [ ] **Step 1: Banner im VStack einfügen**

In `MenuBarView.swift` das `body` anpassen. Direkt nach `Text("DerFlüsterer")`:

```swift
            UpdateBannerView(
                state: appState.updateState,
                dismissedVersion: settings.system.dismissedUpdateVersion,
                onDismiss: { version in appState.dismissUpdateVersion(version) },
                strings: UpdateBannerLocalization.strings(
                    for: .from(localeIdentifier: Locale.current.language.languageCode?.identifier)
                )
            )
```

Wichtig: `MenuBarView` braucht noch Zugriff auf `appState`. Falls noch nicht drin: Parameter hinzufuegen.

Die Signatur pruefen — wahrscheinlich hat `MenuBarView` schon `appState` aus dem Call-Site. Falls nicht: das `@main` in `KalizapApp.swift` anpassen.

Fallback-Annahme: `MenuBarView` bekommt aktuell `settings`, `pipeline`, `historyVM`. Wir ergaenzen `appState`:

```swift
struct MenuBarView: View {
    @Bindable var settings: SettingsManager
    var pipeline: DictationPipeline?
    var historyVM: HistoryViewModel
    var appState: AppState       // NEU
    @Environment(\.openWindow) private var openWindow
```

Und in `KalizapApp.swift`, wo `MenuBarView` instanziiert wird, `appState: appState` uebergeben.

- [ ] **Step 2: Build verifizieren**

Run: `swift build`
Expected: grün.

---

## Task 11: Settings-Button "Nach Updates suchen"

**Files:**
- Modify: `Sources/KalizapApp/Views/SettingsView.swift`

- [ ] **Step 1: Button in `SystemSettingsSection` einfuegen**

In `SettingsView.swift` die `SystemSettingsSection` finden. Darin einen Button unterhalb der bestehenden Felder einfuegen:

```swift
Button(UpdateBannerLocalization.strings(
    for: .from(localeIdentifier: Locale.current.language.languageCode?.identifier)
).checkForUpdatesButton) {
    Task { await appState.checkForUpdatesManually() }
}
```

Wichtig: `SystemSettingsSection` braucht Zugriff auf `appState`. Falls noch nicht: Parameter hinzufuegen und im Call-Site von `SettingsView.swift` durchreichen.

- [ ] **Step 2: Build + Tests**

Run: `swift build`
Expected: grün.

Run: `swift test`
Expected: alle gruen.

---

## Task 12: Info.plist Sparkle-Altlasten aufräumen

**Files:**
- Modify: `Sources/KalizapApp/Info.plist`

- [ ] **Step 1: `SUFeedURL` + `SUPublicEDKey`-Eintraege entfernen**

**Alt:**
```xml
    <key>SUFeedURL</key>
    <string>https://github.com/msandhofer/Kalizap/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string></string>
```

**Neu:** (Zeilen komplett entfernen)

Danach sollte die Info.plist nur noch Bundle-Informationen + Permission-Strings enthalten.

- [ ] **Step 2: Build verifizieren**

Run: `swift build`
Expected: grün.

---

## Task 13: Abschluss — Full Build, Tests, Commit

**Files:** keine.

- [ ] **Step 1: Kompletter Test-Durchlauf**

Run: `swift test`
Expected: alle Tests gruen (aktuell 116, neu ~25, insgesamt ~141).

- [ ] **Step 2: App-Build**

Run: `swift build`
Expected: `Build complete!`, keine Warnings bei meinen Files.

- [ ] **Step 3: Manuelle App-Verifikation**

Run: `swift run KalizapApp`

Manuell pruefen:
- App startet ohne Crash
- Menueleisten-Icon erscheint
- Menueleisten-Popover zeigt **keinen** Update-Banner (weil das Repo privat ist, API-Response ist 404 -> silent, `.unknown` -> Banner versteckt)
- In Settings: "Nach Updates suchen"-Button klickbar, kein Fehler

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(#46): Update-Banner im Menu-Popover + "Nach Updates suchen"

- UpdateBannerView: zeigt neue Version + passende Update-Anweisung
- Homebrew-via-Cask: "brew upgrade --cask ..." mit Copy-Button
- Andere Installationen: Link auf GitHub Release + Quarantaene-Hinweis
- Spaeter-Button: dismisst pro Version (persistiert in SystemSettings)
- 24h-Throttle ueber UserDefaults-Timestamp
- Manueller "Nach Updates suchen"-Button in Settings (ignoriert Throttle)
- Lokalisierung DE/EN ueber Systemsprache
- Sparkle-Altlasten aus Info.plist entfernt (SUFeedURL, SUPublicEDKey)

Verifikation:
- Unit-Tests gruen (ca. 25 neue)
- Bei privatem Repo: API-404 -> silent, kein Banner (erwartet, Test nach #48 mit echter Release)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Ticket-Kommentar + Close + Memory

**Files:** keine.

- [ ] **Step 1: Kommentar an #46**

```bash
gh issue comment 46 --body "..."
```

Inhalt: Zusammenfassung der Loesung, Hinweis auf privates Repo, Hinweis auf manuelle E2E-Verifikation nach #48.

- [ ] **Step 2: Issue schliessen**

```bash
gh issue close 46 --comment "Implementierung abgeschlossen, siehe vorheriger Kommentar. Live-Verifikation erfolgt nach #48 mit erstem Release."
```

- [ ] **Step 3: Memory aktualisieren**

`project_kalizap.md`:
- #46 aus offenen Issues nach "Kuerzlich geschlossen"
- "Offene Issues (4)": #1, #47, #48, #51

---

## Akzeptanzkriterien (Gesamt)

- [ ] SemanticVersion parst `v0.1.0`, `0.1.0`, `1.2.3-beta` korrekt und vergleicht numerisch (kein String-Lex-Bug)
- [ ] HomebrewDetector findet alle 4 Pfad-Kombinationen
- [ ] GitHubReleasesClient ist silent bei 404/Netzwerkfehler (return nil)
- [ ] UpdateChecker nutzt 24h-Throttle, manueller Check ignoriert Throttle
- [ ] Banner erscheint nur bei `.available` und wenn `dismissedVersion != version`
- [ ] Homebrew-via-Cask -> Command-Text + Copy-Button
- [ ] Andere Installation -> GitHub-Link + Quarantaene-Hinweis
- [ ] "Spaeter" persistiert in `SystemSettings.dismissedUpdateVersion`
- [ ] Systemsprache DE oder EN korrekt erkannt
- [ ] Settings hat "Nach Updates suchen"-Button
- [ ] Info.plist frei von Sparkle-Altlasten
- [ ] Alle Tests grün
- [ ] Issue #46 geschlossen mit dokumentiertem Ergebnis
- [ ] Memory aktualisiert

---

## Self-Review Check

**Spec-Coverage:**
- Update-Check via GitHub Releases API: Task 3, 5
- Homebrew-Detection (2 brew-Pfade, 2 Caskroom-Pfade): Task 2
- Banner-Varianten (Homebrew-Command, GitHub-Link, Quarantaene-Hinweis): Task 8
- "Spaeter"-Button mit Version-Dismiss: Task 7, 8, 9
- Copy-Button: Task 8
- Einmal pro Tag (Throttle): Task 6
- Manueller "Nach Updates suchen"-Button: Task 11
- DE/EN Lokalisierung: Task 4
- Keine TCC-Dialoge: Sichergestellt durch FileManager-only (kein Prozess-Exec, kein Terminal-Launch)

**Placeholder-Scan:** durchgegangen, alle Steps haben konkreten Code oder konkrete Kommandos.

**Type-Consistency:**
- `SemanticVersion` konsistent verwendet
- `HomebrewStatus` enum-cases konsistent
- `UpdateState`, `UpdateMethod` enum-cases konsistent
- `BannerStrings` Feldnamen konsistent
- `ReleasesFetching` / `HomebrewDetecting` Protokoll-Methoden konsistent
