# DerFlüsterer

Native macOS Voice-to-Text App mit lokaler Whisper-Transkription und optionaler Claude-Korrektur. Menu-Bar-App, Hotkey-gesteuert, mit DeepFilterNet3 Rauschunterdrückung.

## Installation

### Homebrew Cask (empfohlen)

```
brew install --cask msandhofer/derfluesterer/derfluesterer
```

> Der Homebrew-Tap ist noch in Vorbereitung (siehe Issue #47). Bis dahin: Direct Download.

### Direct Download (GitHub Releases)

1. Neueste Version von [GitHub Releases](https://github.com/msandhofer/Fluesterclon/releases) herunterladen
2. ZIP entpacken und `DerFlüsterer.app` nach `/Applications/` ziehen
3. Quarantäne-Flag entfernen — entweder per Rechts-Klick → **Öffnen** → **Öffnen** (einmaliger Gatekeeper-Bypass), oder im Terminal:
   ```
   xattr -d com.apple.quarantine /Applications/DerFlüsterer.app
   ```

Hinweis: Die App ist nicht notarized (bewusste Entscheidung — kein Apple Developer Program). Bei jedem Update muss der Quarantäne-Bypass erneut ausgeführt werden. Über den Homebrew-Weg passiert das automatisch.

### Voraussetzungen

- macOS 26+ (Tahoe)
- Apple Silicon (ARM64)
- Anthropic API-Key für die LLM-Korrektur (optional — ohne Key läuft reine Transkription)

## Lizenz

[PolyForm Noncommercial License 1.0.0](LICENSE) — Copyright 2026 Mathias Sandhofer

Nicht-kommerzielle Nutzung (privat, Forschung, Lernen, Beitragen) ist frei erlaubt. Kommerzielle Nutzung, Weiterverkauf oder Einbindung in kommerzielle Produkte ist nicht gestattet. Bei Interesse an einer kommerziellen Lizenz bitte anfragen.
