# DerFlüsterer — Grill-Session Ergebnis

Stand: 2026-03-24

## Kernfunktion
Taste halten → Mikrofon aktiv → Whisper transkribiert lokal → Claude Haiku korrigiert/formatiert → Text an Cursorposition eingefügt. Ziel: unter 700ms nach Loslassen.

## Architektur
- Native macOS App, Swift/SwiftUI
- Kein Backend, lokale App + Claude API
- SwiftData für Persistenz
- WhisperKit für lokale ASR (CoreML, Apple Silicon)
- Sparkle für Auto-Updates
- API-Key im macOS Keychain

## Audio-Pipeline
- AVAudioEngine für Mikrofon-Input
- Streaming-Transkription angestrebt, Batch als Fallback
- Deutsch-optimiertes Whisper-Modell (noch zu recherchieren)
- Muss auf Apple Silicon M-Chip optimiert laufen

## LLM-Korrektur
- Claude Haiku 4.5 via Anthropic API
- Ein System-Prompt, Kontext-Modus als Parameter
- 5 Aufgaben: Grammatik/Rechtschreibung, Füllwörter entfernen, Satzstruktur glätten, Zeichensetzung, Kontext-Anpassung
- Korrektur-Intensität konfigurierbar (Toggles: umformulieren, kürzen, Satzstruktur umstellen)
- Retry 1x bei Fehler, dann Fallback auf Raw-Transkript + Notification
- Timeout: 800ms

## Text-Einfügen
- Clipboard + Cmd+V Simulation + Clipboard-Restore (Primary)
- Accessibility API als Fallback
- Bei Fehler: Text bleibt im Clipboard, User wird benachrichtigt
- Prüft vorher ob Textfeld im Fokus (AXFocusedUIElement)
- Clipboard-Restore erst beim nächsten Diktat bei pendingInClipboard

## Hotkey
- Konfigurierbar, Default: rechte Option-Taste gedrückt halten
- Push-to-Talk UND Toggle-Modus unterstützt

## UI & Feedback
- Menu-Bar-App mit pulsierendem Icon + Waveform/Pegel während Aufnahme
- Kein Floating Overlay
- Sanfter Sound bei Start/Ende der Aufnahme (abschaltbar)
- Menu-Bar-Popover: Status, letzte 3 Diktate (One-Click-Copy), Quick-Toggles
- Hauptfenster: History + Statistiken
- Settings als eigene macOS Scene (⌘,)
- Setup-Assistent beim ersten Start (Mikrofon, Accessibility, API-Key, Modell)

## History
- Chronologische Liste mit Zeitstempel
- Durchsuchbar (Volltextsuche)
- Löschbar
- Limit konfigurierbar (Default: 100)
- Datenmodell: ID, Timestamp, Raw-Transkript, Korrigierter Text, Sprache, Kontext-Modus, Ziel-App, Dauer, Verarbeitungszeit

## Settings (gruppiert)
- Audio: Mikrofon, Sprache (DE/EN), Sounds
- Hotkey: Taste, Push-to-Talk/Toggle
- Korrektur: Kontext-Modus (formell/informell/neutral/auto mit App-Mapping), Intensität (3 Toggles), Wörterbuch, LLM-Timeout
- System: Auto-Start, History-Limit, Debug-Modus
- API-Key: Keychain, validiert beim Start, Status in Menu Bar

## Statistiken (im MVP)
- Anzahl Diktate (gesamt/heute/Woche)
- Gesamtzahl Wörter
- Durchschnittliche WPM
- Streak (Tage in Folge)
- Durchschnittliche Verarbeitungszeit

## Pipeline-Architektur
- Event-basiert (Combine/AsyncStream)
- Streaming: Transkription beginnt während Aufnahme
- Rapid Re-Dictation: Neues Diktat startet sofort, vorheriges läuft im Hintergrund
- 9 Module: HotkeyManager, AudioRecorder, TranscriptionEngine, TextCorrector, TextInserter, DictationPipeline, DictationStore, SettingsManager, UI Layer

## Nicht im MVP
- Windows-Support
- Snippets
- Auto-Wörterbuch aus Korrekturen
- Live-Transkription im Overlay
- Offline-LLM-Korrektur
- Automatische Spracherkennung
- Favoriten in History
- Homebrew-Distribution

## Technische Risiken
1. Globaler Hotkey (rechte Option-Taste)
2. Streaming-Transkription (Chunk-Grenzen)
3. Clipboard-Restore Timing
4. Text-Einfügen in geschützte Apps
5. Swift-Lernkurve

## Motivation
Kostenersparnis: wenige Cent API-Kosten vs. 12€/Monat Wispr Flow
