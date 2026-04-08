# Testdaten-Konvention

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
swift run SpeechSwiftTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de

# Einzelne Datei testen (whisper.cpp)
swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model base

# Alle Dateien im Verzeichnis (Batch mit WER)
swift run SpeechSwiftTestCLI batch Tests/Testdaten de

# Parameter-Sweep
swift run SpeechSwiftTestCLI sweep Tests/Testdaten de

# JSON-Ausgabe fuer automatisierte Auswertung
swift run SpeechSwiftTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --json
```

## Testdateien

| Datei | Inhalt | Besonderheit |
|-------|--------|--------------|
| Testaufnahme1 | Kurzer Satz ueber Pferd | ~8.5s, einfach |
| Testaufnahme2 | Langer Text, Nonsense-Woerter | ~38s, Fachbegriffe |
| Testaufnahme3 | Stille | ~10s, kein Sprachinhalt |
| Testaufnahme4 | Ein Wort ("kurz") | ~1.4s, sehr kurz |
| Testaufnahme5 | Medium-langer Satz | ~14s, Techbegriffe |
| Testaufnahme6 | Vorgelesener Fachtext | Entwickler-Doku |
| Testaufnahme7 | Vorgelesene YAML-Struktur | Technische Begriffe, EN gemischt |
| Testaufnahme8 | Frei erfundener Text | Natuerlicher Sprachfluss |
| Testaufnahme9 | Sehr kurzer Satz | ~2-3s |
| Testaufnahme10 | Langer freier Text | ~60s+, Website-Planung |

## Neue Testdateien hinzufuegen

1. Audio aufnehmen und als `Testaufnahme<N>.m4a` speichern
2. Erwarteten Text in `Testaufnahme<N>.txt` schreiben (UTF-8, kein BOM)
3. Audio-Dateien werden via Git LFS versioniert (`*.m4a` in `.gitattributes`)
