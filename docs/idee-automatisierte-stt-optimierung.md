# Idee: Automatisierte STT-Optimierung im Wettstreit

**Status:** Idee fuer die Zukunft
**Datum:** 2026-04-08

## Konzept

Zwei Claude-Instanzen optimieren parallel zwei STT-Backends (Qwen3-ASR und whisper.cpp) im Wettstreit. Beide bekommen dieselben Testdateien und dasselbe Ziel. Am Ende vergleichen wir die Ergebnisse.

## Voraussetzungen

### 1. Streaming-Simulation (stream-file Modus)
Ein CLI-Modus der eine Audio-Datei chunk-weise durch VAD+ASR schickt, als waere es Live-Audio. Komplett deterministisch und reproduzierbar — kein Mikrofon noetig.

### 2. Automatisches Scoring
WER-Berechnung (Word Error Rate) gegen die `.txt`-Erwartungsdateien. Oder einfacher: Levenshtein-Distanz auf Wort-Ebene. Ausgabe als einzelne Zahl pro Datei + Durchschnitt.

### 3. Testdateien
10 Audio-Dateien mit erwarteten Texten:
- Verschiedene Laengen (1s, 3s, 5s, 10s, 20s, 40s)
- Verschiedene Sprechstile (langsam, schnell, mit Pausen, ohne Pausen)
- Verschiedene Inhalte (Alltag, Fachbegriffe, gemischt DE/EN)
- Jeweils mit `.txt` Erwartungsdatei

### 4. Zwei Feature-Branches

| Branch A: Qwen3-ASR | Branch B: whisper.cpp |
|---------------------|----------------------|
| speech-swift Parameter tunen | whisper.cpp Parameter tunen |
| Quantisierung testen (4/6/8-bit) | Q5_0 + CoreML testen |
| Segment-Parameter optimieren | VAD-Parameter optimieren |
| Context-Prompting testen | Prompt-Engineering testen |
| Modell-Varianten (0.6B vs 1.7B) | Modell-Varianten (turbo, german-finetuned) |

### 5. Optimierungsziel
Jede Instanz bekommt:
- Die 10 Testdateien mit erwarteten Texten
- Ein Scoring-Skript (WER + Latenz)
- Klares Ziel: **Minimiere WER bei Latenz < 600ms nach Stop**
- Freie Hand bei Parametern innerhalb ihres Backends

## Erwarteter Nutzen

- Objektiver Vergleich beider Backends unter gleichen Bedingungen
- Entdeckung von Optimierungen die ein Mensch uebersehen wuerde
- Parallelisierung der Arbeit
- Reproduzierbare Ergebnisse

## Offene Fragen

- Wie lange soll jede Instanz optimieren? (Zeitbudget)
- Duerfen die Instanzen die Architektur aendern oder nur Parameter?
- Wie wird der Vergleich am Ende strukturiert?
- Brauchen wir einen Schiedsrichter (dritte Instanz)?
