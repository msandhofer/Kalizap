# Latenz-Optimierung (Issue #36)

Forschungsergebnisse zur Reduktion der Gesamt-Latenz zwischen Loslassen des
Aufnahmeknopfes und Text-Paste.

**Ausgangslage:** ~2800ms Gesamt-Latenz (CoreML, large-v3-turbo, M1 MacBook Air)

## 1. Insert Delay (Clipboard Restore)

### Problem

Nach dem Paste (Cmd+V) wartet die App `restoreDelay` Millisekunden, bevor das
Clipboard mit dem urspruenglichen Inhalt wiederhergestellt wird. Der bisherige
Wert (500ms) ist uebertrieben konservativ.

### Testverfahren

Automatisiertes Tool (`InsertDelayTest`): Setzt Clipboard, simuliert Cmd+V,
wartet konfigurierbaren Delay, ueberschreibt Clipboard mit Marker-Text,
verifiziert ob der richtige oder der Marker-Text eingefuegt wurde.

- **TextEdit, Terminal.app**: Verifikation via AppleScript
- **iTerm2**: Verifikation via AppleScript (`contents` von iTerm2 Session)
- **Ghostty**: Verifikation via Screenshot (kein AppleScript-Support)

### Ergebnisse

| App | Methode | Minimum (100% Erfolg) | Getestete Delays |
|-----|---------|----------------------|------------------|
| TextEdit | AppleScript | 10ms | 0, 5, 10, 15, 20, 25, 50, 75, 100ms |
| Terminal.app | AppleScript | 20ms | 0, 5, 10, 15, 20, 25, 50, 75, 100ms |
| iTerm2 | AppleScript + Screenshot | 10ms | 0, 5, 10, 15, 20, 25, 50, 100, 150, 200, 250ms |
| Ghostty | Screenshot | 25ms | 10, 25, 50, 100, 150, 200, 250ms |

**Details:**
- 0ms: 0% Erfolg bei allen Apps (Clipboard wird sofort ueberschrieben)
- 5ms: Flaky (60-90% je nach App und Textlaenge)
- 10ms: 100% bei TextEdit und iTerm2, flaky bei Terminal und Ghostty
- 20ms: 100% bei allen ausser Ghostty
- 25ms: 100% bei allen Apps

Jede Kombination (App x Delay x Textlaenge) wurde 10x wiederholt.
Textlaengen: "kurz" (4 chars), mittel (107 chars), lang (383 chars).

### Entscheidung

**restoreDelay = 100ms** (von 500ms). Konservative Sicherheitsmarge: 4x ueber
dem hoechsten gemessenen Minimum (Ghostty 25ms). Beruecksichtigt vereinzelte
statistische Ausreisser bei niedrigeren Werten.

**Einsparung: ~400ms**

### Rohdaten

- `rohdaten/insert-delay-textedit.json` — Vollstaendige TextEdit-Ergebnisse (9 Delays x 3 Texte x 10 Reps)
- `rohdaten/insert-delay-terminal.json` — Vollstaendige Terminal-Ergebnisse (14 Delays x 3 Texte x 10 Reps)
- iTerm2-Ergebnisse: Automatisierter Test (10ms=100%) + Screenshot-Verifikation
- Ghostty-Ergebnisse: Screenshot-basiert (10ms=FAIL, 25ms=OK)
- Screenshots: `Tools/InsertDelayScreenshotTest/screenshots/`

---

## 2. StreamWait (Finaler Delta-Decode)

### Problem

Nach dem Stop wartet die App auf den finalen Delta-Decode: das Audio zwischen
der letzten VAD-Stille-Boundary und dem Stop-Zeitpunkt muss noch transkribiert
werden. Das dauert ~700-1300ms (CoreML, large-v3-turbo).

### Optimierungsansaetze

Drei Ansaetze wurden getestet:

**Ansatz A — Kuerzerer Fallback:** Fallback-Decode-Intervall von 4s auf 1.5-2s
reduzieren. Mehr Zwischen-Decodes = kleineres Delta bei Stop.

**Ansatz B — Partial-Accept (PA):** Wenn das Delta bei Stop kleiner als eine
Schwelle ist, den Delta-Decode ueberspringen und den bisherigen Text verwenden.

**Ansatz C — Tail-Decode:** Waehrend der Aufnahme periodisch das Audio nach der
letzten VAD-Boundary spekulativ dekodieren und cachen. Bei Stop den Cache
verwenden statt neu zu dekodieren.

### Testverfahren

Neuer CLI-Command `stream-whisper` im WhisperCppTestCLI: Simuliert die
WhisperTranscriptionEngine-Logik deterministisch auf Audiodateien. Bildet
VAD-Polling (200ms), kumulative Re-Decodes, Fallback-Decodes, Tail-Decodes
und den finalen Delta-Decode nach.

`sweep-whisper`: Parameter-Grid ueber alle Kombinationen mit Pareto-Analyse.

### Parameter-Grid

- Fallback-Intervall: 1.5, 2.0, 3.0, 4.0s
- Tail-Intervall: 0 (aus), 1.0, 1.5, 2.0s
- Partial-Accept: 0 (aus), 0.3, 0.5, 1.0s
- Filterregel: tail > 0 nur bei fb >= 3.0 (vermeidet doppelten CPU-Overhead)
- **40 Konfigurationen x 10 Audiodateien = 400 Einzellaeufe**

Modell: large-v3-turbo mit CoreML Encoder, M1 MacBook Air.

### Ergebnisse (Sweep-Uebersicht)

Die vollstaendige Tabelle aller 40 Konfigurationen:

| # | FB | Tail | PA | Avg WER | Avg SW | Avg TD |
|---|-----|------|-----|---------|--------|--------|
| 1 | 1.5 | 0 | 0 | 33.0% | 720ms | 39100ms |
| 2 | 1.5 | 0 | 0.3 | 32.8% | 593ms | 42062ms |
| 3 | 1.5 | 0 | 0.5 | 21.7% | 514ms | 41641ms |
| 4 | 1.5 | 0 | 1.0 | 20.6% | 306ms | 42927ms |
| 5 | 2.0 | 0 | 0 | 31.2% | 628ms | 35739ms |
| 6 | 2.0 | 0 | 0.3 | 31.2% | 628ms | 34842ms |
| 7 | 2.0 | 0 | 0.5 | 20.1% | 691ms | 37986ms |
| 8 | 2.0 | 0 | 1.0 | 19.1% | 299ms | 35552ms |
| 9 | 3.0 | 0 | 0 | 38.4% | 657ms | 24625ms |
| 10 | 3.0 | 0 | 0.3 | 38.4% | 710ms | 24638ms |
| 11 | 3.0 | 0 | 0.5 | 27.3% | 606ms | 25138ms |
| 12 | 3.0 | 0 | 1.0 | 27.3% | 746ms | 27897ms |
| 13 | 3.0 | 1.0 | 0 | 38.4% | 802ms | 51287ms |
| 14 | 3.0 | 1.0 | 0.3 | 38.4% | 444ms | 50078ms |
| 15 | 3.0 | 1.0 | 0.5 | 27.3% | 177ms | 45567ms |
| 16 | 3.0 | 1.0 | 1.0 | 27.6% | 0ms | 37180ms |
| 17 | 3.0 | 1.5 | 0 | 38.4% | 635ms | 33137ms |
| 18 | 3.0 | 1.5 | 0.3 | 38.4% | 386ms | 33368ms |
| 19 | 3.0 | 1.5 | 0.5 | 27.3% | 118ms | 35125ms |
| 20 | 3.0 | 1.5 | 1.0 | 27.3% | 118ms | 35667ms |
| 21 | 3.0 | 2.0 | 0 | 38.4% | 650ms | 37289ms |
| 22 | 3.0 | 2.0 | 0.3 | 38.4% | 408ms | 35077ms |
| 23 | 3.0 | 2.0 | 0.5 | 27.3% | 292ms | 33404ms |
| 24 | 3.0 | 2.0 | 1.0 | 27.3% | 200ms | 32340ms |
| 25 | 4.0 | 0 | 0 | 37.8% | 712ms | 18735ms |
| 26 | 4.0 | 0 | 0.3 | 37.8% | 741ms | 19008ms |
| 27 | 4.0 | 0 | 0.5 | 26.7% | 659ms | 19776ms |
| 28 | 4.0 | 0 | 1.0 | 26.3% | 445ms | 19412ms |
| 29 | 4.0 | 1.0 | 0 | 37.8% | 700ms | 36881ms |
| 30 | 4.0 | 1.0 | 0.3 | 37.8% | 352ms | 36129ms |
| 31 | 4.0 | 1.0 | 0.5 | 26.7% | 170ms | 38232ms |
| 32 | 4.0 | 1.0 | 1.0 | 26.5% | 0ms | 36078ms |
| 33 | 4.0 | 1.5 | 0 | 37.8% | 643ms | 29165ms |
| 34 | 4.0 | 1.5 | 0.3 | 37.8% | 386ms | 27654ms |
| 35 | 4.0 | 1.5 | 0.5 | 26.7% | 232ms | 27449ms |
| 36 | 4.0 | 1.5 | 1.0 | 26.3% | 79ms | 28524ms |
| 37 | 4.0 | 2.0 | 0 | 37.8% | 659ms | 24523ms |
| 38 | 4.0 | 2.0 | 0.3 | 37.8% | 560ms | 23904ms |
| 39 | 4.0 | 2.0 | 0.5 | 26.7% | 488ms | 24173ms |
| 40 | 4.0 | 2.0 | 1.0 | 26.3% | 260ms | 24166ms |

### Analyse: Per-File Textvergleich

Die letzten 3 Woerter sind bei PA=0.3 und PA=0.5 identisch mit der Baseline
fuer alle Testdateien. Erst bei PA=1.0 geht bei Testaufnahme7 ein Wort verloren
("Punkt." am Ende fehlt).

Vollstaendige Per-File-Analyse: `rohdaten/per-file-analyse.txt`

### Analyse: Kumulative Re-Decode Qualitaet (Ansatz A)

Vergleich der Baseline-Konfigurationen (kein Tail, kein PA):

| Fallback | WER | StreamWait | Total Decode |
|----------|-----|-----------|-------------|
| 1.5s | 33.0% | 720ms | 39100ms |
| 2.0s | 31.2% | 628ms | 35739ms |
| 3.0s | 38.4% | 657ms | 24625ms |
| 4.0s | 37.8% | 712ms | 18735ms |

Kuerzerer Fallback hat leicht bessere WER (31-33% vs 37-38%), aber doppelte
CPU-Last (TD). Die WER-Verbesserung stammt hauptsaechlich von Testaufnahme4
(1.4s) und Testaufnahme9 (3.3s) — sehr kurze Aufnahmen, bei denen haeufigere
Zwischen-Decodes bessere initial_prompt-Kontexte liefern.

### Analyse: WER-Anomalie bei Partial-Accept

Die Avg WER *sinkt* mit aggressiverem PA (37.8% → 26.3%). Das ist kontraintuitiv.
Ursache: Whisper halluziniert bei kurzen Delta-Segmenten (z.B. Testaufnahme4
"kurz" wird als "Gut. -" dekodiert, WER=200%). PA ueberspringt diesen
fehlerhaften Delta-Decode, was die Avg WER senkt. Die Per-File Analyse zeigt,
dass normale Aufnahmen (>8s) identische WER haben unabhaengig von PA.

### Bekannte Limitierungen

1. **10 Testdateien, ein Sprecher:** Die Ergebnisse koennten fuer andere
   Sprecher, Pausenmuster oder Hintergrundgeraeusche anders ausfallen.
2. **Kein Truncation-Test:** Die Testdateien enden nach natuerlichem
   Sprechende. Ein abrupter Stop (z.B. mitten im Satz) wurde nicht getestet.
   PA koennte in diesem Fall Text abschneiden.
3. **Thermisches Throttling:** Der M1 Air throttelt bei Dauerlast (~30% unter
   Max-Frequenz). Die absoluten Decode-Zeiten im Sweep sind pessimistisch.
   Relative Verhaeltnisse bleiben valide.

### Entscheidung: Verworfen

Die Sweep-Ergebnisse zeigten vielversprechende StreamWait-Reduktionen in der
Simulation (bis zu 0ms). **Die Implementierung in der echten App zeigte jedoch
keinen messbaren Nutzen** (StreamWait blieb bei ~1000-1500ms).

### Ursache: Simulationsfehler

Die Simulation modellierte die Nebenlaefigkeit nicht korrekt:

- **Simulation:** Decodes passieren "zwischen" Ticks ohne simulierte Zeit zu
  verbrauchen. Beim "Stop" ist kein Decode im Gange. StreamWait = nur der
  finale Delta-Decode (der durch Tail-Cache/PA wegfaellt).

- **Reale App:** Decodes dauern ~800ms Echtzeit. Waehrend eines Decodes kommt
  neues Audio vom Mikrofon. Beim Stop ist mit ~60% Wahrscheinlichkeit ein
  Decode im Gange. StreamWait = Restzeit des laufenden Decodes + ggf.
  Delta-Decode. Der Tail-Cache/PA eliminiert nur den Delta-Decode, aber der
  laufende Decode (~800ms) dominiert die Wartezeit.

Verifiziert durch verbose-log Analyse: In 11 Diktaten lief in JEDEM Fall ein
Decode waehrend des StreamWait. Tail-Cache-Accept und Partial-Accept griffen
korrekt (2 von 11 Faellen), aber erst NACHDEM der laufende Decode fertig war.

**Learning:** Simulationen muessen gegen das reale System verifiziert werden,
bevor Ergebnisse abgeleitet werden. Ein einzelner Vergleich (Simulation vs.
App-Log) haette den Fehler sofort aufgedeckt.

### Rohdaten

Die Sweep-Daten bleiben als Referenz erhalten. Die WER-Vergleiche sind weiterhin
valide (Textqualitaet ist korrekt gemessen). Nur die StreamWait-Werte der
Simulation sind nicht auf die reale App uebertragbar.

- `rohdaten/streamwait-sweep-clean.json` — Alle 400 Einzelergebnisse (bereinigtes JSON)
- `rohdaten/streamwait-sweep.json` — Original-Sweep-Output (inkl. Fortschrittsausgabe)
- `rohdaten/per-file-analyse.txt` — Letzte 3 Woerter pro Datei und Konfiguration

---

## Gesamt-Einsparung

| Phase | Vorher | Nachher | Einsparung |
|-------|--------|---------|------------|
| Insert (restoreDelay) | 540ms | 140ms | **400ms** |
| StreamWait (Tail+PA) | — | — | **0ms (verworfen)** |
| **Summe** | | | **~400ms** |

Gesamt-Latenz: ~2800ms → ~2400ms. Das Ziel (<1000ms) ist mit den verbleibenden
Phasen (STT ~870ms, LLM ~840ms) ohne grundlegende Architektur-Aenderungen
nicht erreichbar. Die Insert-Optimierung ist der einzige reale Gewinn.

Der dominierende Flaschenhals (StreamWait ~1000ms) ist inhaerent: Whisper-Decodes
auf CoreML/M1 dauern ~800ms pro Aufruf, und beim Stop muss der laufende Decode
abgewartet werden. Eine Reduktion wuerde schnellere Hardware, ein kleineres
Modell oder eine fundamental andere Streaming-Architektur erfordern.

---

## Test-Tools

Alle Tools liegen unter `Tools/` und sind als SPM-Targets im Package.swift
eingebunden:

- **InsertDelayTest**: Automatisierter Clipboard-Paste-Delay-Test fuer TextEdit/Terminal
- **InsertDelayScreenshotTest**: Screenshot-basierter Paste-Test fuer Apps ohne AppleScript
- **WhisperCppTestCLI stream-whisper**: Deterministische Streaming-Simulation (WER-Vergleich valide, StreamWait-Werte nicht realistisch)
- **WhisperCppTestCLI sweep-whisper**: Parameter-Grid mit Pareto-Analyse
