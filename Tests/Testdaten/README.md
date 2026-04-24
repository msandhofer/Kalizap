# Testdaten-Konvention

## Hinweis zur Public-Distribution

Audio-Aufnahmen und Transkripte werden **nicht** im Repository versioniert (biometrische Daten, Privacy). Eigene Testdaten werden lokal abgelegt und sind via `.gitignore` ausgeschlossen (Muster `Tests/Testdaten/*.m4a` und `Tests/Testdaten/Testaufnahme*.txt`). Nur diese README und die JSON-Messdaten-Files im Verzeichnis sind Teil des Repositories.

## Dateiformat

Jede Testdatei besteht aus einem Audio-/Text-Paar:

- `<name>.m4a` -- Audio-Aufnahme (auch .wav, .mp3, .caf, .aiff, .flac)
- `<name>.txt` -- Manuell transkribierte Erwartung (plain text, UTF-8)

Alternativ wird auch `<name>.expected.txt` erkannt.

Die `.txt`-Datei enthält den exakten erwarteten Text der Transkription. Bei Stille (keine Sprache) bleibt die `.txt`-Datei leer.

## WER-Berechnung

Die Word Error Rate wird gegen den `.txt`-Inhalt berechnet:
- Case-insensitive
- Interpunktion wird ignoriert
- Levenshtein-Distanz auf Wort-Ebene

## Verwendung

```bash
# Einzelne Datei testen (Qwen3-ASR)
swift run SpeechSwiftTestCLI stream-file Tests/Testdaten/meineaufnahme.m4a de

# Einzelne Datei testen (whisper.cpp)
swift run WhisperCppTestCLI stream-file Tests/Testdaten/meineaufnahme.m4a de --model base

# Alle Dateien im Verzeichnis (Batch mit WER)
swift run SpeechSwiftTestCLI batch Tests/Testdaten de

# Parameter-Sweep
swift run SpeechSwiftTestCLI sweep Tests/Testdaten de

# JSON-Ausgabe fuer automatisierte Auswertung
swift run SpeechSwiftTestCLI stream-file Tests/Testdaten/meineaufnahme.m4a de --json
```

## Eigene Testdateien hinzufuegen

1. Audio aufnehmen und als `<name>.m4a` (oder `.wav` etc.) speichern
2. Erwarteten Text in `<name>.txt` schreiben (UTF-8, kein BOM)
3. Beide Dateien bleiben lokal, werden nicht committed (gitignored).
