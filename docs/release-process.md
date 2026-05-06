# Release-Prozess

Schritt-für-Schritt-Anleitung für einen Kalizap-Release. Distribution erfolgt via [Homebrew-Cask im eigenen Tap](https://github.com/msandhofer/homebrew-kalizap), zusätzlich als GitHub-Release-Asset für direkten Download.

## Einmalige Vorbereitung

Pro Maintainer-Maschine einmal:

```bash
# App-Secret generieren (für AES-GCM-Verschlüsselung der API-Keys)
./Scripts/generate-app-secret.sh

# Git-LFS-Assets ziehen (libdf.a, DeepFilterNet3_onnx.tar.gz)
git lfs pull
```

Tap-Repository einmalig anlegen:

```bash
gh repo create msandhofer/homebrew-kalizap --public --description "Homebrew Tap für Kalizap"
```

## Release durchführen

### 1. Version bumpen

In `Sources/KalizapApp/Info.plist` den Wert `CFBundleShortVersionString` auf die neue Version setzen (z. B. `0.2.0`). Optional `CFBundleVersion` (Build-Nummer) inkrementieren.

```bash
plutil -replace CFBundleShortVersionString -string "0.2.0" Sources/KalizapApp/Info.plist
git add Sources/KalizapApp/Info.plist
git commit -m "chore: bump version to 0.2.0"
git push origin main
```

### 2. Build + Bundle + ZIP

```bash
./Scripts/build-app-bundle.sh
```

Output: `dist/Kalizap.app` und `dist/Kalizap-${VERSION}.zip`. Das Skript gibt am Ende die SHA256-Summe aus, die später im Cask gebraucht wird.

### 3. Manuelle Funktions-Verifikation

Vor dem Release einmal die App lokal testen:

```bash
open dist/Kalizap.app
```

Prüfen:
- Menübar-Icon erscheint
- Settings-Fenster lässt sich öffnen
- API-Key kann eingetragen und persistiert werden
- Hotkey-Aufnahme + Whisper-Transkription funktioniert
- Update-Banner erscheint nicht (oder mit korrekter Version-Logik)

Bei Mikrofon-Erstanfrage: Berechtigung erteilen. Bei Quarantäne-Bypass-Frage: Rechtsklick → Öffnen → Öffnen.

### 4. Git-Tag setzen

```bash
git tag v0.2.0
git push origin v0.2.0
```

### 5. GitHub-Release anlegen

```bash
gh release create v0.2.0 \
    dist/Kalizap-0.2.0.zip \
    --title "v0.2.0" \
    --notes "Release-Notes hier"
```

Alternativ via Web-UI: https://github.com/msandhofer/Kalizap/releases/new

### 6. Cask-Formula im Tap-Repo aktualisieren

Im Tap-Repo `homebrew-kalizap` die Datei `Casks/kalizap.rb` öffnen und folgende zwei Zeilen aktualisieren:

```ruby
version "0.2.0"
sha256 "<aus Schritt 2 ausgegebener SHA256>"
```

Commit + Push:

```bash
cd ../homebrew-kalizap
git add Casks/kalizap.rb
git commit -m "kalizap 0.2.0"
git push origin main
```

### 7. Cask-Update verifizieren

Auf einem zweiten Rechner (oder nach `brew uninstall --cask kalizap`):

```bash
brew tap msandhofer/kalizap
brew install --cask kalizap
```

Erwartetes Ergebnis: App wird in `/Applications/Kalizap.app` installiert, Quarantäne-Flag automatisch entfernt, App startet ohne Gatekeeper-Prompt.

## Hotfix für Cask-Formula

Falls in der Cask-Formula ein Bug entdeckt wird (z. B. falscher zap-Pfad), reicht ein Tap-Repo-Commit ohne neuen App-Release:

```bash
cd ../homebrew-kalizap
# Casks/kalizap.rb bearbeiten
git commit -am "fix(cask): zap-Pfad korrigiert"
git push origin main
```

User bekommen den Fix beim nächsten `brew update`.

## Release-Notes-Konventionen

Strukturvorschlag für `--notes` in Schritt 5:

```
## Neu
- ...

## Geändert
- ...

## Behoben
- ...

## Bekannte Einschränkungen
- App ist nicht notarized — Erst-Installation via Direct-Download verlangt Quarantäne-Bypass (Rechtsklick → Öffnen). Über Homebrew-Cask passiert das automatisch.
```

## Rollback

Bei einem fehlerhaften Release:

1. Cask-Formula im Tap-Repo zurück auf vorherige Version + SHA256
2. GitHub-Release als "Pre-release" markieren oder ganz entfernen (`gh release delete v0.2.0`)
3. Tag löschen: `git tag -d v0.2.0` lokal, `git push origin :v0.2.0` remote

## Referenzen

- Build-Skript: [`Scripts/build-app-bundle.sh`](../Scripts/build-app-bundle.sh)
- Distribution-Entscheidung: Issue #39 (Kommentar vom 2026-04-23)
- Tap-Setup-Issue: #45
- Public-Schaltung-Issue: #46
