# Rename DerFluesterer → Kalizap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Umbenennung der App von `DerFluesterer` / `Fluesterclon` zu `Kalizap`. Volles Rename über alle drei Ebenen: GitHub-Repo, App-Display-Name, Bundle-ID, Swift-Module, Filesystem-Pfade, Doku. Als Nebenprodukt wird das Repo-Migration-Problem (orphaned LFS-Objekte) gelöst, indem das alte Repo gelöscht und der aktuelle Stand auf das neue Repo gepusht wird — mit Issue-Transfer via GitHub-native Funktion (behält Timestamps, Autoren, Kommentare).

**Architecture:** Zwei klar getrennte Phasen. Phase A ist Git-/GitHub-Ops ohne Code-Aenderung. Phase B ist ein groesserer Code-Refactor ueber viele Files, bleibt aber mechanisch — Suchen & Ersetzen plus Ordner-Umbenennungen. Verifiziert durch `swift build` + `swift test` nach jedem Teilschritt. Am Ende manuelle App-Verifikation.

**Tech Stack:** Git, GitHub CLI (`gh`), Swift Package Manager, Info.plist.

---

## Betroffene Namens-Ebenen und Mapping

| Alt | Neu |
|---|---|
| GitHub-Repo `msandhofer/Fluesterclon` | `msandhofer/Kalizap` |
| App-Display-Name `DerFlüsterer` | `Kalizap` |
| Bundle-ID `com.sandhofer.derfluisterer` | `com.sandhofer.kalizap` |
| Swift-Library-Target `DerFluisterer` | `Kalizap` |
| Swift-Executable-Target `DerFluistererApp` | `KalizapApp` |
| Quell-Ordner `Sources/DerFluisterer/` | `Sources/Kalizap/` |
| Quell-Ordner `Sources/DerFluistererApp/` | `Sources/KalizapApp/` |
| Test-Ordner `Tests/DerFluistererTests/` | `Tests/KalizapTests/` |
| App-Support-Pfad `~/Library/Application Support/DerFluisterer/` | `~/Library/Application Support/Kalizap/` |
| Homebrew-Cask `msandhofer/derfluesterer/derfluesterer` | `msandhofer/kalizap/kalizap` |
| Swift-Package-Name im `Package.swift` | `Kalizap` |

---

## File Structure — was umbenannt/modifiziert wird

### Ordner-Umbenennung
- `Sources/DerFluisterer/` → `Sources/Kalizap/`
- `Sources/DerFluistererApp/` → `Sources/KalizapApp/`
- `Tests/DerFluistererTests/` → `Tests/KalizapTests/`

### Dateien-Umbenennung
- `Sources/DerFluistererApp/DerFluistererApp.swift` → `Sources/KalizapApp/KalizapApp.swift` (innerhalb verschobener Ordner)

### Modifizierte Dateien

| Pfad | Aenderung |
|---|---|
| `Package.swift` | Package-Name, Target-Namen, Pfade, `@main`-Struct-Namen in Executable |
| `Sources/KalizapApp/Info.plist` | `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier` |
| `Sources/KalizapApp/KalizapApp.swift` | `@main struct DerFluistererApp: App` → `@main struct KalizapApp: App`, App-Support-Pfad-Literal |
| `Sources/KalizapApp/AppState.swift` | GitHub-Repo-Owner/-Repo, Homebrew-Cask-Command-Literal |
| Alle `*.swift` in `Sources/Kalizap{,App}/` und `Tests/KalizapTests/` | `import DerFluisterer` → `import Kalizap` |
| Alle `Tools/*/main.swift` | `import DerFluisterer` → `import Kalizap` |
| `Tools/PromptJailbreakTest/main.swift` | Repo-URL in Kommentar |
| `Scripts/generate-app-secret.sh` | Pfad `Sources/DerFluistererApp/AppSecret.swift` → `Sources/KalizapApp/AppSecret.swift` |
| `.gitignore` | Pfad `Sources/DerFluistererApp/AppSecret.swift` → `Sources/KalizapApp/AppSecret.swift` |
| `README.md` | App-Name, Repo-URL, Homebrew-Cask-Command, Build-Instruktionen |
| `docs/security.md` | Datei-Pfade, App-Name |
| `docs/build-secret.md` | Pfad `Sources/DerFluistererApp/AppSecret.swift` → `Sources/KalizapApp/AppSecret.swift` |
| `Tests/Testdaten/README.md` | App-Name, Tool-Paths |

### Unveraendert
- `Sources/CDeepFilter/` — Externes Framework, eigener Namespace
- `Tools/STTTestCommon/` — Name OK, bleibt (`STTTestCommon` ist kein App-Name)
- `Tools/PromptJailbreakTest/` — Tool-Name neutral, bleibt
- Alle anderen `Tools/*` Executable-Target-Namen
- `Sources/CDeepFilter/lib/libdf.a` (LFS, bleibt)
- `Sources/CDeepFilter/lib/DeepFilterNet3_onnx.tar.gz` (LFS, bleibt)

---

## Phase A — Repo-Migration (Phase A besteht aus Tasks A1–A7)

### Task A1: Issue-Backup als JSON

**Files:**
- Create: `/tmp/fluesterclon-issues-backup.json`

- [ ] **Step 1: Script zum Backup aller Issues inkl. Kommentare**

Run:
```bash
for num in $(gh issue list --state all --limit 100 --json number --jq '.[].number'); do
    gh issue view $num --json number,title,body,state,labels,createdAt,updatedAt,comments,closed,closedAt
    echo ","
done | jq -s . > /tmp/fluesterclon-issues-backup.json
```

Expected: Datei `/tmp/fluesterclon-issues-backup.json` enthaelt Array mit 51 Issue-Objekten (inkl. offener + geschlossener).

- [ ] **Step 2: Sanity-Check**

Run: `jq 'length' /tmp/fluesterclon-issues-backup.json`
Expected: `51`

Run: `jq '.[0].title, .[0].number' /tmp/fluesterclon-issues-backup.json`
Expected: `"Observability: Fallback-Gruende..."` / `51` (neuestes Issue)

---

### Task A2: Neues Repo `Kalizap` anlegen

**Files:** keine (remote operation).

- [ ] **Step 1: Neues GitHub-Repo anlegen**

Run:
```bash
gh repo create msandhofer/Kalizap --private --description "macOS Voice-to-Text mit Whisper + Claude Haiku"
```

Expected: Output bestaetigt `Created repository msandhofer/Kalizap on GitHub`

- [ ] **Step 2: Verifikation**

Run: `gh repo view msandhofer/Kalizap --json name,visibility,isEmpty`
Expected: `{"name":"Kalizap","visibility":"PRIVATE","isEmpty":true}`

---

### Task A3: Lokale Historie auf neues Repo pushen

**Files:** keine.

- [ ] **Step 1: Origin-URL auf neues Repo umstellen**

Run: `git remote set-url origin https://github.com/msandhofer/Kalizap.git`
Run: `git remote -v`
Expected: zeigt `origin  https://github.com/msandhofer/Kalizap.git (fetch)` + `(push)`

- [ ] **Step 2: Push main + LFS**

Run: `git push -u origin main`
Expected: Upload aller 83 Commits + LFS-Objekte (`libdf.a`, `DeepFilterNet3_onnx.tar.gz`). Erfolgreich abgeschlossen.

- [ ] **Step 3: Tags pushen (optional, kein Tag aktuell wichtig außer pre-testdaten-rewrite als Safety)**

Run: `git push origin --tags`
Expected: Tag `pre-testdaten-rewrite` hochgeladen.

- [ ] **Step 4: Sanity-Check**

Run: `gh repo view msandhofer/Kalizap --json isEmpty,pushedAt`
Expected: `isEmpty: false`, `pushedAt` aktuelle Zeit.

---

### Task A4: Issues transferieren

**Files:** keine.

- [ ] **Step 1: Transfer-Script schreiben**

Erstelle `/tmp/transfer-issues.sh` mit Inhalt:

```bash
#!/bin/bash
set -e
SRC_REPO="msandhofer/Fluesterclon"
DST_REPO="msandhofer/Kalizap"

for num in $(seq 1 51); do
    echo "--- Transferring issue #$num ---"
    gh issue transfer $num "$DST_REPO" --repo "$SRC_REPO" || echo "SKIP #$num (not transferable)"
    sleep 1
done
```

Ausfuehrbar machen: `chmod +x /tmp/transfer-issues.sh`

- [ ] **Step 2: Script ausfuehren**

Run: `bash /tmp/transfer-issues.sh`
Expected: Fuer jede Issue-Nummer 1–51 erscheint eine Ausgabe. Einige koennen SKIPs sein (geschlossene muessen vor Transfer ggf. reopened werden, siehe Step 3).

**Hinweis:** `gh issue transfer` erfordert moeglicherweise, dass Issues offen sind. Falls geschlossene Issues nicht transferiert werden koennen, Step 3 als Workaround.

- [ ] **Step 3: Workaround fuer geschlossene Issues (falls notwendig)**

Falls der Transfer in Step 2 bei geschlossenen Issues fehlschlaegt:

```bash
# Fuer jedes Issue: reopen, transfer, dann am Ziel wieder close
for num in $(seq 1 51); do
    state=$(gh issue view $num --repo msandhofer/Fluesterclon --json state --jq '.state')
    if [ "$state" = "CLOSED" ]; then
        gh issue reopen $num --repo msandhofer/Fluesterclon
    fi
    gh issue transfer $num msandhofer/Kalizap --repo msandhofer/Fluesterclon
    sleep 1
done
```

Nach erfolgreichem Transfer die geschlossenen Issues im neuen Repo wieder schliessen. Liste der geschlossenen Issues vorher merken:
```bash
gh issue list --state closed --repo msandhofer/Fluesterclon --limit 100 --json number --jq '.[].number' > /tmp/closed-issues.txt
```

Dann im neuen Repo schliessen:
```bash
for num in $(cat /tmp/closed-issues.txt); do
    gh issue close $num --repo msandhofer/Kalizap
done
```

---

### Task A5: Transfer-Verifikation

**Files:** keine.

- [ ] **Step 1: Issue-Count am neuen Repo**

Run: `gh issue list --state all --repo msandhofer/Kalizap --limit 100 --json number | jq 'length'`
Expected: `51`

- [ ] **Step 2: Nummern-Bereich**

Run: `gh issue list --state all --repo msandhofer/Kalizap --limit 100 --json number --jq '[.[].number] | min, max'`
Expected: `1` und `51`

- [ ] **Step 3: Spot-Check inhaltliche Integritaet**

Run: `gh issue view 44 --repo msandhofer/Kalizap --json title,state,body --jq '.title, .state'`
Expected: `"API-Key-Storage: Keychain-Abhängigkeit evaluieren und ggf. ersetzen"`, `"CLOSED"`

Run: `gh issue view 51 --repo msandhofer/Kalizap --json title,state --jq '.title, .state'`
Expected: `"Observability: Fallback-Gruende..."`, `"OPEN"`

- [ ] **Step 4: Kommentare-Check (auf einem Issue mit vielen Kommentaren)**

Run: `gh issue view 44 --repo msandhofer/Kalizap --comments | head -30`
Expected: Kommentar-Texte und Timestamps vorhanden (nicht leer).

---

### Task A6: Altes Repo löschen

**Files:** keine.

**WARNUNG:** Zerstoererisch, nicht rueckgaengig. Vor Ausfuehrung SICHER sein, dass A5 alle Issues am neuen Ort verifiziert hat.

- [ ] **Step 1: Finale Bestaetigung vor Loeschung**

Run: `gh repo view msandhofer/Fluesterclon --json url,isEmpty,pushedAt`

Pruefen: das ist tatsaechlich das alte Repo, das geloescht werden soll.

- [ ] **Step 2: Repo loeschen**

**Erfordert explizite User-Bestaetigung im Chat vor Ausfuehrung.**

Run: `gh repo delete msandhofer/Fluesterclon --yes`
Expected: `Deleted repository msandhofer/Fluesterclon`

- [ ] **Step 3: Verifikation**

Run: `gh repo view msandhofer/Fluesterclon 2>&1 | head -2`
Expected: Fehlermeldung `GraphQL: Could not resolve to a Repository with the name ...`

---

### Task A7: Tag-Cleanup

**Files:** keine.

- [ ] **Step 1: Safety-Tag entfernen (lokal)**

Run: `git tag -d pre-testdaten-rewrite`
Expected: `Deleted tag 'pre-testdaten-rewrite'`

- [ ] **Step 2: Safety-Tag entfernen (remote, falls schon gepusht)**

Run: `git push origin :refs/tags/pre-testdaten-rewrite 2>&1 || echo "tag not present on remote"`
Expected: entweder `deleted ... pre-testdaten-rewrite` oder `tag not present on remote`.

---

## Phase B — App-Code-Rename (Tasks B1–B16)

### Task B1: Package.swift umstellen

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Package-Name + Library-Target + Library-Dependency-Namen aendern**

Im `Package.swift`:

**Alt:**
```swift
let package = Package(
    name: "DerFluisterer",
    ...
    products: [
        .library(name: "DerFluisterer", targets: ["DerFluisterer"]),
    ],
    ...
```

**Neu:**
```swift
let package = Package(
    name: "Kalizap",
    ...
    products: [
        .library(name: "Kalizap", targets: ["Kalizap"]),
    ],
    ...
```

Weiter im `targets`-Array:

**Alt:**
```swift
        .target(
            name: "DerFluisterer",
            dependencies: [
                "CDeepFilter",
            ]
        ),
        .executableTarget(
            name: "DerFluistererApp",
            dependencies: ["DerFluisterer"],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/DeepFilterNet3_onnx.tar.gz"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/DerFluistererApp/Info.plist",
                ]),
            ]
        ),
```

**Neu:**
```swift
        .target(
            name: "Kalizap",
            dependencies: [
                "CDeepFilter",
            ]
        ),
        .executableTarget(
            name: "KalizapApp",
            dependencies: ["Kalizap"],
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/DeepFilterNet3_onnx.tar.gz"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/KalizapApp/Info.plist",
                ]),
            ]
        ),
```

Weitere Referenzen im gleichen File:

**Alt-Pattern:** `dependencies: ["DerFluisterer"]`
**Neu-Pattern:** `dependencies: ["Kalizap"]`

(Alle `Tools/*`-Executable-Targets, die als Dependency `"DerFluisterer"` haben, umstellen.)

**Alt-Pattern:** `name: "DerFluistererTests", dependencies: ["DerFluisterer"]`
**Neu-Pattern:** `name: "KalizapTests", dependencies: ["Kalizap"]`

- [ ] **Step 2: Noch kein Build — Tasks B2/B3 muessen auch laufen, bevor Build funktioniert**

---

### Task B2: Quell-Ordner umbenennen

**Files:** (Ordner-Umbenennung via `git mv`)

- [ ] **Step 1: Library-Ordner**

Run:
```bash
git mv Sources/DerFluisterer Sources/Kalizap
```
Expected: ohne Ausgabe (Erfolg).

- [ ] **Step 2: App-Ordner**

Run:
```bash
git mv Sources/DerFluistererApp Sources/KalizapApp
```

- [ ] **Step 3: App-Entry-Point-Datei umbenennen**

Run:
```bash
git mv Sources/KalizapApp/DerFluistererApp.swift Sources/KalizapApp/KalizapApp.swift
```

---

### Task B3: Test-Ordner umbenennen

**Files:**

- [ ] **Step 1: Test-Ordner**

Run:
```bash
git mv Tests/DerFluistererTests Tests/KalizapTests
```

---

### Task B4: import-Statements in allen Swift-Files ersetzen

**Files:** alle `.swift` unter `Sources/Kalizap/`, `Sources/KalizapApp/`, `Tests/KalizapTests/`, `Tools/*/`.

- [ ] **Step 1: Suchen aller Stellen mit `import DerFluisterer`**

Run: `grep -rln "import DerFluisterer" Sources/ Tests/ Tools/`

Expected: Liste von Files, die den Import nutzen.

- [ ] **Step 2: Alle Imports ersetzen**

Run:
```bash
grep -rln "import DerFluisterer" Sources/ Tests/ Tools/ | xargs sed -i '' 's/import DerFluisterer/import Kalizap/g'
```

- [ ] **Step 3: Verifikation — keine `import DerFluisterer` mehr**

Run: `grep -rln "import DerFluisterer" Sources/ Tests/ Tools/`
Expected: leer (keine Ausgabe).

Run: `grep -rln "import Kalizap" Sources/ Tests/ Tools/ | head -5`
Expected: mindestens 5 Files mit dem neuen Import.

---

### Task B5: `@main`-Struct im App-Entry-Point umbenennen

**Files:**
- Modify: `Sources/KalizapApp/KalizapApp.swift`

- [ ] **Step 1: Struct-Namen aendern**

Im File:

**Alt:**
```swift
@main
struct DerFluistererApp: App {
```

**Neu:**
```swift
@main
struct KalizapApp: App {
```

- [ ] **Step 2: Alle weiteren Referenzen auf `DerFluistererApp` im selben File**

Run:
```bash
grep -n "DerFluistererApp" Sources/KalizapApp/KalizapApp.swift
```

Ergebnis manuell pruefen und `DerFluistererApp` durch `KalizapApp` ersetzen, wo es sich auf den Struct-Namen bezieht (nicht auf Pfade etc.).

---

### Task B6: Info.plist Bundle-Namen, Display-Name, Bundle-ID

**Files:**
- Modify: `Sources/KalizapApp/Info.plist`

- [ ] **Step 1: Bundle-Metadata aendern**

**Alt:**
```xml
    <key>CFBundleName</key>
    <string>DerFlüsterer</string>
    <key>CFBundleDisplayName</key>
    <string>DerFlüsterer</string>
    <key>CFBundleIdentifier</key>
    <string>com.sandhofer.derfluisterer</string>
```

**Neu:**
```xml
    <key>CFBundleName</key>
    <string>Kalizap</string>
    <key>CFBundleDisplayName</key>
    <string>Kalizap</string>
    <key>CFBundleIdentifier</key>
    <string>com.sandhofer.kalizap</string>
```

Auch den `NSSpeechRecognitionUsageDescription` aktualisieren:

**Alt:**
```xml
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>DerFluesterer nutzt Spracherkennung um Ihre Diktate in Text umzuwandeln.</string>
```

**Neu:**
```xml
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Kalizap nutzt Spracherkennung um Ihre Diktate in Text umzuwandeln.</string>
```

---

### Task B7: App-Support-Pfad im Code ändern

**Files:**
- Modify: `Sources/KalizapApp/KalizapApp.swift`
- Suche alle Stellen mit `"DerFluisterer"` als String-Literal in `Sources/`

- [ ] **Step 1: Finden aller Referenzen**

Run: `grep -rn '"DerFluisterer"' Sources/`
Expected: Liste mit mindestens einer Zeile in `KalizapApp.swift` (der `appSupport.appendingPathComponent("DerFluisterer", ...)`-Aufruf).

- [ ] **Step 2: Ersetzen**

In `Sources/KalizapApp/KalizapApp.swift`:

**Alt:**
```swift
        let baseDir = appSupport.appendingPathComponent("DerFluisterer", isDirectory: true)
```

**Neu:**
```swift
        let baseDir = appSupport.appendingPathComponent("Kalizap", isDirectory: true)
```

- [ ] **Step 3: Weitere Referenzen in Production-Code pruefen**

Run: `grep -rn '"DerFluisterer"' Sources/ Tests/`

Jede Fundstelle pruefen:
- Falls String-Literal fuer App-Support-Pfad: durch `"Kalizap"` ersetzen
- Falls nur Display-Name in Log-Meldungen: ggf. auch ersetzen (einheitlicher Brand)

- [ ] **Step 4: `"DerFlüsterer"` (mit Umlaut) ebenfalls pruefen**

Run: `grep -rn 'DerFlüsterer' Sources/ Tests/`

Jede Fundstelle: entscheiden, ob durch `Kalizap` ersetzt.

---

### Task B8: GitHub-Repo-URL in `AppState.swift` umstellen

**Files:**
- Modify: `Sources/KalizapApp/AppState.swift`

- [ ] **Step 1: Werte aendern**

Im `triggerUpdateCheckIfNeeded`-Block:

**Alt:**
```swift
        let releases = GitHubReleasesClient(owner: "msandhofer", repo: "Fluesterclon")
        let brew = HomebrewDetector()
        let checker = UpdateChecker(
            currentVersion: currentVersion,
            releasesClient: releases,
            homebrewDetector: brew,
            githubReleaseBaseURL: URL(string: "https://github.com/msandhofer/Fluesterclon/releases/latest")!,
            homebrewCaskCommand: "brew upgrade --cask msandhofer/derfluesterer/derfluesterer"
        )
```

**Neu:**
```swift
        let releases = GitHubReleasesClient(owner: "msandhofer", repo: "Kalizap")
        let brew = HomebrewDetector()
        let checker = UpdateChecker(
            currentVersion: currentVersion,
            releasesClient: releases,
            homebrewDetector: brew,
            githubReleaseBaseURL: URL(string: "https://github.com/msandhofer/Kalizap/releases/latest")!,
            homebrewCaskCommand: "brew upgrade --cask msandhofer/kalizap/kalizap"
        )
```

---

### Task B9: `HomebrewDetector` Caskroom-Pfade anpassen

**Files:**
- Modify: `Sources/Kalizap/Services/HomebrewDetector.swift`

- [ ] **Step 1: Caskroom-Pfade**

**Alt:**
```swift
    private static let caskroomPaths = [
        "/opt/homebrew/Caskroom/derfluesterer",
        "/usr/local/Caskroom/derfluesterer",
    ]
```

**Neu:**
```swift
    private static let caskroomPaths = [
        "/opt/homebrew/Caskroom/kalizap",
        "/usr/local/Caskroom/kalizap",
    ]
```

- [ ] **Step 2: Test anpassen**

In `Tests/KalizapTests/HomebrewDetectorTests.swift` pruefen und anpassen:

Run: `grep -n "derfluesterer" Tests/KalizapTests/HomebrewDetectorTests.swift`

Fundstellen:
- `fake.existingPaths = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/derfluesterer"]`
- `fake.existingPaths = ["/usr/local/bin/brew", "/usr/local/Caskroom/derfluesterer"]`

Ersetze `derfluesterer` mit `kalizap`:

**Alt:**
```swift
        fake.existingPaths = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/derfluesterer"]
```

**Neu:**
```swift
        fake.existingPaths = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/kalizap"]
```

und analog fuer den Intel-Pfad.

---

### Task B10: Build verifizieren (grobe Korrektur-Runde)

**Files:** keine.

- [ ] **Step 1: Build versuchen**

Run: `swift build 2>&1 | tail -20`
Expected: entweder Success, oder Fehler-Meldungen, die auf noch nicht umgestellte Referenzen hinweisen.

Falls Fehler: Fehler-Meldungen manuell auswerten und fehlende Stellen anpassen (typischerweise `import` oder Target-Pfad-Referenzen).

- [ ] **Step 2: Tests laufen lassen**

Run: `swift test 2>&1 | grep -E "Test run with|failures" | tail -3`
Expected: alle Tests gruen (152 Tests, 0 failures).

---

### Task B11: `Scripts/generate-app-secret.sh` Pfad-Referenz

**Files:**
- Modify: `Scripts/generate-app-secret.sh`

- [ ] **Step 1: Pfad aendern**

**Alt:**
```bash
TARGET="Sources/DerFluistererApp/AppSecret.swift"
```

**Neu:**
```bash
TARGET="Sources/KalizapApp/AppSecret.swift"
```

- [ ] **Step 2: Die existierende AppSecret-Datei umziehen, damit sie an der neuen Stelle steht**

Run: `mv Sources/DerFluistererApp/AppSecret.swift Sources/KalizapApp/AppSecret.swift 2>/dev/null || true`

**Achtung:** Falls Sources/DerFluistererApp/ schon nicht mehr existiert (wurde in B2 umbenannt), dann ist die Datei moeglicherweise schon an der richtigen Stelle — pruefen mit `ls Sources/KalizapApp/AppSecret.swift`.

- [ ] **Step 3: `.gitignore` anpassen**

**Alt:**
```
Sources/DerFluistererApp/AppSecret.swift
```

**Neu:**
```
Sources/KalizapApp/AppSecret.swift
```

---

### Task B12: README.md umbauen

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Alle Treffer ersetzen**

Inhalt pruefen:

Run: `grep -n "DerFlüsterer\|DerFluesterer\|Fluesterclon\|derfluesterer\|DerFluisterer" README.md`

Ersetzen (in jeweiligem Kontext):
- `DerFlüsterer` → `Kalizap`
- `DerFluesterer` → `Kalizap`
- `Fluesterclon` → `Kalizap` (in Repo-URL)
- `derfluesterer` → `kalizap` (in Cask-URL)
- `DerFluisterer` → `Kalizap` (Identifier)

- [ ] **Step 2: Titel-Headline anpassen**

**Alt:**
```markdown
# DerFlüsterer
```

**Neu:**
```markdown
# Kalizap
```

- [ ] **Step 3: Inhaltliche Anpassung (kurzer Untertitel ggf. ergaenzen)**

Nach dem Titel-Block koennte ein Kurz-Hinweis ergaenzt werden, z. B. "Voice-to-Text" bleibt relevant. Keine pflicht, aber sinnvoll.

- [ ] **Step 4: Markdown-Sanity**

Run: `grep -n "Fluesterclon\|DerFl\|derfluesterer\|DerFluisterer" README.md`
Expected: leer.

---

### Task B13: docs/security.md umbauen

**Files:**
- Modify: `docs/security.md`

- [ ] **Step 1: Treffer ersetzen**

Run: `grep -n "DerFlüsterer\|DerFluesterer\|Fluesterclon\|DerFluisterer" docs/security.md`

Ersetzen analog B12:
- `~/Library/Application Support/DerFluisterer/` → `~/Library/Application Support/Kalizap/`

- [ ] **Step 2: Sanity**

Run: `grep -n "DerFl\|DerFluisterer\|Fluesterclon" docs/security.md`
Expected: leer.

---

### Task B14: docs/build-secret.md umbauen

**Files:**
- Modify: `docs/build-secret.md`

- [ ] **Step 1: Treffer ersetzen**

Pfad-Referenzen:
- `Sources/DerFluistererApp/AppSecret.swift` → `Sources/KalizapApp/AppSecret.swift`
- `~/Library/Application Support/DerFluisterer/` → `~/Library/Application Support/Kalizap/`
- App-Name-Referenzen im Fliesstext

- [ ] **Step 2: Sanity**

Run: `grep -n "DerFluisterer\|DerFl\|Fluesterclon" docs/build-secret.md`
Expected: leer.

---

### Task B15: Tests/Testdaten/README.md anpassen

**Files:**
- Modify: `Tests/Testdaten/README.md`

- [ ] **Step 1: Tool-Aufrufe inspizieren**

Run: `grep -n "DerFlüsterer\|DerFluesterer\|Fluesterclon\|DerFluisterer" Tests/Testdaten/README.md`

- [ ] **Step 2: Ersetzen**

Falls Treffer (vermutlich keine dort, weil die README nur STT-Tool-Aufrufe beschreibt): analog anpassen.

---

### Task B16: Final-Build + Full-Test

**Files:** keine.

- [ ] **Step 1: Kompletter Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` ohne Fehler.

- [ ] **Step 2: Alle Tests**

Run: `swift test 2>&1 | grep -E "Test run with|failures" | tail -3`
Expected: alle ~152 Tests gruen, 0 failures.

- [ ] **Step 3: Suchen nach restlichen alten Namen**

Run: `grep -rln "DerFluisterer\|DerFluestereApp\|DerFluistererApp\|derfluesterer\|Fluesterclon" Sources/ Tests/ Tools/ Scripts/ docs/ README.md Package.swift .gitignore`

Expected: leer oder nur unkritische Treffer (z. B. in Kommentaren, die historischen Bezug haben — entscheiden pro Fall).

**Falls Treffer:**
- Wenn Code-Referenz: muss ersetzt werden
- Wenn Kommentar-Erwaehnung (z. B. "frueher DerFluisterer"): OK, aber ueberdenken ob Aussage noch relevant ist

---

### Task B17: Manuelle App-Verifikation

**Files:** keine, Verifikation.

- [ ] **Step 1: App starten**

Run: `swift run KalizapApp`
Expected: App startet, Menueleisten-Icon erscheint.

- [ ] **Step 2: API-Key neu eintragen**

Der App-Support-Pfad hat sich geaendert (`DerFluisterer` → `Kalizap`). Die alten verschluesselten Credentials liegen im alten Pfad, der neue Pfad ist leer. Also:
- Settings oeffnen
- API-Key eintragen
- Speichern

- [ ] **Step 3: Verifikation FS**

Run: `ls -la "$HOME/Library/Application Support/Kalizap/"`
Expected: Datei `anthropic-api-key.enc` existiert, `rw-------`.

- [ ] **Step 4: App-Neustart + Diktat-Test**

App beenden, neu starten. Kurzes Diktat ausfuehren, korrigierter Text sollte eingefuegt werden.

- [ ] **Step 5: Alten App-Support-Ordner aufraeumen (optional, nicht destructive)**

Run: `ls -la "$HOME/Library/Application Support/DerFluisterer/" 2>&1 | head -5`
Expected: falls existiert, alte Credentials-Datei sichtbar.

Der User kann manuell entscheiden, den alten Ordner zu loeschen:
```bash
rm -rf "$HOME/Library/Application Support/DerFluisterer/"
```

Diese Aktion **nicht vom Script** ausfuehren lassen — user-Entscheidung, da destruktiv.

---

### Task B18: Squash + Final-Commit

**Files:** keine.

- [ ] **Step 1: Alle Aenderungen stagen**

Run: `git add -A`

- [ ] **Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore: Rename DerFluesterer/Fluesterclon -> Kalizap

Umbenennung der App ueber alle Ebenen:
- Swift-Package + Library/Executable-Targets: DerFluisterer -> Kalizap, DerFluistererApp -> KalizapApp
- Ordner: Sources/DerFluisterer{,App} -> Sources/Kalizap{,App}, Tests/DerFluistererTests -> Tests/KalizapTests
- Bundle-ID: com.sandhofer.derfluisterer -> com.sandhofer.kalizap
- Display-Name: DerFluesterer -> Kalizap
- App-Support-Pfad: ~/Library/Application Support/DerFluisterer -> .../Kalizap
- Homebrew-Cask: msandhofer/derfluesterer -> msandhofer/kalizap
- Repo: msandhofer/Fluesterclon -> msandhofer/Kalizap (Migration + Issue-Transfer)
- Alle Doku + Skripte angepasst

Breaking: Bestandsnutzer muessen API-Key neu eintragen (App-Support-Pfad geaendert).
Alle 152 Tests gruen, App manuell verifiziert.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Push**

Run: `git push origin main`
Expected: Commit geht auf msandhofer/Kalizap.

---

## Akzeptanzkriterien (Gesamt)

### Phase A (Repo-Migration)
- [ ] Neues Repo `msandhofer/Kalizap` angelegt und mit kompletter lokaler Historie gepusht
- [ ] Alle 51 Issues im neuen Repo, Nummern 1–51, states korrekt (open/closed), Kommentare und Timestamps erhalten
- [ ] Altes Repo `msandhofer/Fluesterclon` geloescht
- [ ] Origin-Remote lokal auf neues Repo zeigt
- [ ] `pre-testdaten-rewrite`-Tag entfernt

### Phase B (Rename)
- [ ] `swift build` grün
- [ ] `swift test` grün (alle ~152 Tests)
- [ ] Keine Referenzen mehr auf `DerFluisterer`, `DerFluistererApp`, `Fluesterclon`, `derfluesterer` in Code/Scripts/Docs (optional: in Git-Historie, was OK)
- [ ] App startet als `KalizapApp`, Bundle-ID `com.sandhofer.kalizap`
- [ ] App-Support-Pfad `~/Library/Application Support/Kalizap/` wird angelegt
- [ ] API-Key neu eintragbar, verschluesselte Datei landet am neuen Pfad
- [ ] Diktat-Flow funktioniert end-to-end
- [ ] Commit vorhanden, auf Remote gepusht

---

## Self-Review Check

**Spec-Coverage:**
- Repo-Rename: Task A2, A3
- Issue-Transfer: Task A4, A5
- Altes Repo loeschen (LFS-Cleanup nebenbei): Task A6
- Swift-Module-Rename: Task B1, B2, B3, B4
- Info.plist-Umbauten: Task B6
- App-Support-Pfad: Task B7
- Homebrew-Cask-Command: Task B8, B9
- Doku-Umbau: Task B12, B13, B14, B15
- App-Secret-Pfad: Task B11
- Build-Verifikation: Task B10, B16
- Manuelle App-Verifikation: Task B17

**Placeholder-Scan:** durchgegangen, konkrete Files und Befehle an jeder Stelle.

**Type-Consistency:** Naming-Mappings (DerFluisterer → Kalizap, DerFluistererApp → KalizapApp, derfluesterer → kalizap) durchgaengig konsistent verwendet.

**Potentielle Stolpersteine:**
- `gh issue transfer` koennte bei geschlossenen Issues scheitern (siehe Task A4 Step 3 Workaround)
- Bei Step B7 koennten weitere String-Literale in AppState oder anderen Files stecken, die das grep nicht sofort findet (z. B. fuer Logging) — Task B16 Step 3 als Catch-All-Grep angelegt
- LFS-Push: Beim ersten `git push` nach Remote-Umstellung muss LFS-Content hochladen — das kann Minuten dauern bei ~160 MB. Geduld.
