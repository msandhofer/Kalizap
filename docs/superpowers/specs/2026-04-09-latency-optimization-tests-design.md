# Issue #36: Latenz-Optimierung — Testkonzept

## Scope

Automatisierte Tests fuer zwei Optimierungsbereiche:

1. **Insert Delay** — Minimalen sicheren `restoreDelay` fuer Clipboard-Restore finden
2. **StreamWait** — Optimale Konfiguration fuer Fallback-Intervall, Tail-Decode und Partial-Accept

Ergebnisse fliessen in die Implementierung der App-Optimierung ein.

---

## Teil 1: Insert Delay Test

### Ziel

Den minimalen `restoreDelay` ermitteln, bei dem der Paste zuverlaessig ankommt, bevor das Clipboard wiederhergestellt wird. Aktuell: 500ms. Ziel: <200ms.

### Testansatz

Ein Swift-Script (oder neuer CLI-Command), das:

1. Ziel-App aktiviert (TextEdit / Terminal)
2. Textfeld fokussiert
3. Bekannten Text ins Clipboard setzt
4. Cmd+V simuliert (CGEvent)
5. Konfigurierbaren Delay wartet
6. Clipboard mit anderem Inhalt ueberschreibt (simuliert Restore)
7. Eingefuegten Text verifiziert

### Verifikation

- **TextEdit**: AppleScript `tell application "TextEdit" to get text of document 1`
- **Terminal**: AppleScript `tell application "Terminal" to get contents of selected tab of front window` — moeglicherweise unzuverlaessig, Alternative: Cmd+A → Cmd+C → Clipboard lesen

### Parameter-Matrix

| Parameter | Werte |
|-----------|-------|
| Delay (ms) | 25, 50, 75, 100, 125, 150, 200, 300, 500 |
| Textlaenge | Kurz (1 Wort), Mittel (1 Satz ~15 Woerter), Lang (3 Saetze ~60 Woerter) |
| Ziel-App | TextEdit, Terminal |
| Wiederholungen | 10 pro Kombination (Zuverlaessigkeit messen) |

**Gesamt: 9 Delays x 3 Laengen x 2 Apps x 10 Reps = 540 Durchlaeufe**

### Texte (aus vorhandenen Testdaten)

- **Kurz**: "kurz" (Testaufnahme4.txt)
- **Mittel**: "Dies ist eine richtige Testaufnahme, die einigermassen lang ist, in der ich etwas ueber das Pferd erzaehle." (Testaufnahme1.txt)
- **Lang**: Testaufnahme8.txt (~61 Woerter, natuerliche Sprache)

### Metriken

- **Erfolgsrate**: Anteil der Durchlaeufe, bei denen der korrekte Text eingefuegt wurde (10/10 = 100%)
- **Ergebnis pro Kombination**: Pass (100% Erfolg) / Fail (< 100%)

### Output

JSON-Report:
```json
{
  "results": [
    {
      "app": "TextEdit",
      "textLength": "short",
      "delayMs": 100,
      "runs": 10,
      "successes": 10,
      "successRate": 1.0
    }
  ],
  "recommendation": {
    "minSafeDelayMs": 100,
    "notes": "100% Erfolg ab 100ms fuer alle Apps und Textlaengen"
  }
}
```

### Implementierung

Neuer Command `insert-delay-test` im **WhisperCppTestCLI** (oder eigenstaendiges Swift-Script).

Benoetigt:
- `NSPasteboard` fuer Clipboard-Operationen
- `CGEvent` fuer Cmd+V Simulation (gleiche Logik wie `CGEventKeystrokeSimulator`)
- `NSWorkspace` / AppleScript fuer App-Aktivierung
- AppleScript fuer Text-Verifikation
- Accessibility-Berechtigung (bereits fuer die App vorhanden)

### Ablauf

```
1. TextEdit oeffnen, neues Dokument
2. Fuer jeden Delay-Wert:
   a. Fuer jede Textlaenge:
      i. 10x wiederholen:
         - Textfeld leeren (Cmd+A, Delete)
         - Test-Text ins Clipboard
         - Cmd+V
         - sleep(delay)
         - Clipboard mit Marker-Text ueberschreiben
         - sleep(200ms) — Verifikations-Pause
         - Eingefuegten Text per AppleScript lesen
         - Vergleich: eingefuegt == erwartet?
3. Gleicher Ablauf fuer Terminal
4. Report generieren
```

---

## Teil 2: StreamWait Parameter Test

### Ziel

Optimale Konfiguration fuer drei Ansaetze finden, die StreamWait von ~1300ms reduzieren:

- **Ansatz A**: Fallback-Intervall verkuerzen (4s → 1.5-2s)
- **Ansatz B**: Partial akzeptieren wenn Delta < Schwelle
- **Ansatz C**: Spekulativer Tail-Decode waehrend Aufnahme

### Herausforderung: Streaming-Simulation

Das bestehende WhisperCppTestCLI `simulateStream()` nutzt Silero-VAD mit Segment-basiertem Decode. Die App nutzt ein anderes Verfahren:

- whisper.cpp's eigene VAD (`detectSilenceBoundaries()`)
- 200ms Polling-Loop
- Kumulatives Re-Decode ab Audio-Start bis VAD-Boundary
- Delta-Decode des Rests nach Stop

Fuer aussagekraeftige Tests brauchen wir einen neuen Command `stream-whisper` der das App-Verhalten simuliert.

### Neuer Command: `stream-whisper`

Simuliert die `WhisperTranscriptionEngine.transcribe()` Logik deterministisch auf einer Audio-Datei:

```
swift run WhisperCppTestCLI stream-whisper <audio-path> [de] \
    --model large-v3_turbo \
    --coreml \
    --fallback-interval 4.0 \
    --tail-interval 0 \
    --partial-accept 0.0 \
    --json
```

**Parameter:**

| Flag | Default | Beschreibung |
|------|---------|-------------|
| `--fallback-interval` | 4.0 | Sekunden ohne VAD-Boundary bis Fallback-Decode (Ansatz A) |
| `--tail-interval` | 0 | Sekunden zwischen spekulativen Tail-Decodes, 0=aus (Ansatz C) |
| `--partial-accept` | 0.0 | Schwelle in Sekunden: Delta < Schwelle → Partial akzeptieren (Ansatz B) |
| `--model` | large-v3_turbo | Whisper-Modell |
| `--coreml` | false | CoreML Encoder verwenden |

### Simulations-Algorithmus

```
Eingabe: Audio-Samples, Parameter
Ausgabe: Finaler Text, StreamWait-Dauer, Decode-Zeiten, CPU-Metriken

1. Audio in 32ms-Chunks aufteilen (wie Mikrofon-Input)
2. Chunks sequenziell "einspielen" (simulierte Echtzeit)
3. Alle 200ms:
   a. detectSilenceBoundaries() auf gesamten bisherigen Buffer
   b. Neue Boundary gefunden?
      → Kumulativer Decode bis Boundary (whisper_full_with_state)
      → Partial-Result speichern, lastDecodedSampleCount merken
   c. Keine Boundary, aber fallbackInterval ueberschritten UND >1s neues Audio?
      → Fallback-Decode
   d. tailInterval > 0 UND tailInterval seit letztem Tail-Decode?
      → Spekulativer Tail-Decode (Samples ab lastDecodedSampleCount)
      → Ergebnis cachen (nicht als Partial ausgeben)

4. "Stop" simulieren (alle Chunks verarbeitet):
   a. Delta = totalSamples - lastDecodedSampleCount
   b. Wenn partialAccept > 0 UND delta/16000 < partialAccept:
      → Letztes Partial (oder cached Tail) als Final verwenden
      → StreamWait = 0ms (kein Decode noetig)
   c. Wenn tailInterval > 0 UND cachedTail vorhanden UND neuesSeitTail < partialAccept:
      → Cached Tail als Final verwenden
      → StreamWait = 0ms
   d. Sonst:
      → Delta-Decode (whisper_full_with_state auf Delta-Samples)
      → StreamWait = Decode-Dauer

5. Finalen Text zusammensetzen: akkumulierter Text + Delta/Tail-Ergebnis
6. WER berechnen gegen Expected-Text
```

### Parameter-Sweep: `sweep-whisper`

Grid-Search ueber StreamWait-Parameter:

| Parameter | Werte |
|-----------|-------|
| fallbackInterval | 1.5, 2.0, 3.0, 4.0 (Baseline) |
| tailInterval | 0 (aus), 1.0, 1.5, 2.0 |
| partialAccept | 0 (aus), 0.3, 0.5, 1.0 |

**Filterregeln** (ungueltige Kombinationen ausschliessen):
- tailInterval > 0 UND fallbackInterval < 3.0 → Skip (doppelter Overhead)
- partialAccept > 0 UND tailInterval > 0 → partialAccept bezieht sich auf Tail-Cache

**Geschaetzte Kombinationen**: ~30 gueltige Konfigurationen
**x 10 Testdateien = ~300 Durchlaeufe**
**Bei ~5-10s pro Durchlauf (mehrere Decodes a 400-800ms bei CoreML) = ~30-50 Minuten Laufzeit**

### Metriken pro Durchlauf

| Metrik | Beschreibung |
|--------|-------------|
| `wer` | Word Error Rate gegen Expected-Text |
| `streamWaitMs` | Dauer des finalen Delta-Decode (oder 0 bei Partial-Accept) |
| `totalDecodeMs` | Kumulative Decode-Zeit aller Partial + Delta Decodes |
| `decodeCount` | Anzahl Decodes waehrend Aufnahme |
| `deltaSeconds` | Audio-Delta nach letztem Decode bei Stop |
| `usedPartial` | true wenn Partial/Tail-Cache statt Delta-Decode verwendet |
| `cpuTimeMs` | Prozess-CPU-Zeit waehrend Simulation (via `ProcessInfo.processInfo.systemUptime` oder `mach_thread_info`) |

### Output

Erweitertes `StreamFileResult` mit zusaetzlichen Feldern:

```json
{
  "file": "Testaufnahme1.m4a",
  "engine": "whisper.cpp-large-v3_turbo",
  "params": {
    "fallbackInterval": 2.0,
    "tailInterval": 1.5,
    "partialAccept": 0.3
  },
  "wer": 0.0,
  "streamWaitMs": 0,
  "totalDecodeMs": 1850,
  "decodeCount": 4,
  "deltaSeconds": 0.2,
  "usedPartial": true,
  "cpuTimeMs": 3200,
  "text": "Dies ist eine richtige Testaufnahme...",
  "expected": "Dies ist eine richtige Testaufnahme..."
}
```

Sweep-Report mit Pareto-Filterung nach WER + StreamWait (statt WER + Latency).

---

## Implementierungsreihenfolge

### Phase 1: Insert Delay Test

1. `InsertDelayTestCommand.swift` im WhisperCppTestCLI (oder eigenes Target)
2. AppleScript-Helfer fuer TextEdit/Terminal Verifikation
3. Durchfuehrung: TextEdit zuerst, dann Terminal
4. Ergebnis: minimaler sicherer Delay

### Phase 2: StreamWait Parameter Test

1. Neue Typen in STTTestCommon: `WhisperStreamParams`, `WhisperStreamResult`
2. `StreamWhisperCommand.swift` — Einzeldatei-Simulation
3. `SweepWhisperCommand.swift` — Parameter-Grid mit Pareto
4. Durchfuehrung: Sweep ueber alle 10 Testdateien
5. Ergebnis: optimale Konfiguration (Fallback/Tail/Partial-Accept)

### Phase 3: App-Implementierung (nach Testauswertung)

1. `restoreDelay` auf getesteten Wert setzen
2. `WhisperTranscriptionEngine` mit optimalen StreamWait-Parametern aktualisieren
3. Integrations-Test mit echtem Diktat

---

## Abhaengigkeiten

- **Accessibility-Berechtigung**: Fuer Insert-Test noetig (CGEvent, AppleScript)
- **CoreML Modell**: Fuer StreamWait-Tests mit `--coreml` muss large-v3-turbo CoreML Encoder geladen sein
- **Testdaten**: Vorhandene 10 Audio-Dateien + Expected-Texts in `Tests/Testdaten/`
- **Issue #35**: Erledigt — Timing-Infrastruktur vorhanden

## Nicht im Scope

- LLM-Latenz-Optimierung (spaeter, separates Issue)
- STT-Engine-Wechsel (bereits in #34 optimiert)
- Neue Testdateien erstellen (vorhandene reichen aus)
