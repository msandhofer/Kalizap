# STT-Engine Vergleichstests

Anleitung zum systematischen Vergleich aller STT-Engines und Modellvarianten.

## Voraussetzungen

- Testdaten in `Tests/Testdaten/` (Audio-Dateien + `.txt` Erwartungsdateien)
- Modelle werden beim ersten Aufruf automatisch heruntergeladen

## 1. Testdaten pruefen

```bash
ls Tests/Testdaten/
```

Jede Audio-Datei braucht eine gleichnamige `.txt` mit dem erwarteten Text.

## 2. Qwen3-ASR (Baseline)

```bash
# Batch: alle Dateien, WER + RTF
swift run SpeechSwiftTestCLI batch Tests/Testdaten de

# Stream-File: simulierte Streaming-Latenz
swift run SpeechSwiftTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de

# Parameter-Sweep: optimale VAD-Parameter finden
swift run SpeechSwiftTestCLI sweep Tests/Testdaten de --json
```

## 3. whisper.cpp — Large v3 Turbo (F16, Standard)

```bash
# Batch
swift run WhisperCppTestCLI batch Tests/Testdaten de --model large-v3_turbo

# Stream-File
swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model large-v3_turbo

# Parameter-Sweep
swift run WhisperCppTestCLI sweep Tests/Testdaten de --model large-v3_turbo --json
```

## 4. whisper.cpp — Large v3 Turbo Q5_0 (quantisiert)

Kleineres Modell (~574 MB vs ~950 MB), potenziell schneller bei minimalem Qualitaetsverlust.

```bash
swift run WhisperCppTestCLI batch Tests/Testdaten de --model large-v3_turbo-q5_0

swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model large-v3_turbo-q5_0
```

## 5. whisper.cpp — German-finetuned Turbo

Auf deutsche Sprache feinabgestimmtes Modell (cstr/whisper-large-v3-turbo-german).

```bash
swift run WhisperCppTestCLI batch Tests/Testdaten de --model german-turbo

swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model german-turbo
```

## 6. whisper.cpp — CoreML Encoder

Nutzt den Apple Neural Engine fuer den Encoder-Teil. Benoetigt ein vorcompiliertes `.mlmodelc` neben dem GGML-Modell.

```bash
swift run WhisperCppTestCLI batch Tests/Testdaten de --model large-v3_turbo --coreml

swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model large-v3_turbo --coreml
```

**Hinweis:** Falls das CoreML-Modell fehlt, laeuft whisper.cpp ohne CoreML weiter (kein Fehler, aber kein Speedup).

## 7. Vergleichstabelle erstellen

Fuer eine vollstaendige Vergleichstabelle alle Batch-Ergebnisse nacheinander ausfuehren und die Zusammenfassungen vergleichen:

| Engine | Modell | Avg RTF | Avg WER | Avg Latenz (stream) |
|--------|--------|---------|---------|---------------------|
| Qwen3-ASR | 4bit | — | — | — |
| whisper.cpp | large-v3_turbo | — | — | — |
| whisper.cpp | large-v3_turbo-q5_0 | — | — | — |
| whisper.cpp | german-turbo | — | — | — |
| whisper.cpp | large-v3_turbo +CoreML | — | — | — |

## JSON-Ausgabe

Fuer automatisierte Auswertung `--json` anhaengen:

```bash
swift run WhisperCppTestCLI stream-file Tests/Testdaten/Testaufnahme1.m4a de --model large-v3_turbo --json
swift run SpeechSwiftTestCLI sweep Tests/Testdaten de --json
```
