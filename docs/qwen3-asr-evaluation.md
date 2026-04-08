# Qwen3-ASR Evaluation — DerFluesterer Prototyp

**Datum:** 2026-04-07
**Modell:** Qwen3-ASR 0.6B MLX 4-bit (`aufklarer/Qwen3-ASR-0.6B-MLX-4bit`)
**Framework:** speech-swift (soniqo/speech-swift, branch main)
**Hardware:** Apple Silicon Mac (Mathias' Entwicklungsmaschine)
**Build:** Swift 6.1, Release-Build, MLX Metal Shaders manuell kompiliert

---

## 1. Zusammenfassung

Qwen3-ASR 0.6B wurde als Prototyp-Backend fuer DerFluisterer evaluiert. Das Modell laeuft on-device via MLX auf Apple Silicon und erreicht ein Real-Time-Factor (RTF) von ~0.07-0.10, was deutlich schneller ist als whisper.cpp (RTF ~0.35 im Vergleich).

### Kernmetriken

| Metrik | Wert |
|--------|------|
| Modell-Groesse | ~680 MB (4-bit quantisiert) |
| Modell laden (kalt) | ~2800-3600ms |
| RTF (ab 3s Audio) | 0.07-0.10 |
| STT-Formel | ~130ms + 75ms x Audio-Sekunden |
| VAD (Silero CoreML) | ~47ms fuer Batch, <1ms pro Chunk |

### Latenz-Ziel: <600ms

| Modus | Typische Latenz nach Stop |
|-------|---------------------------|
| Batch (kurzes Diktat, 5-8s) | 400-700ms |
| Batch (langes Diktat, 38s) | 3300ms |
| Stream (mit Segmentierung) | **56-95ms** |

Streaming mit VAD-Segmentierung erreicht das <600ms Ziel zuverlaessig, da waehrend der Aufnahme bereits transkribiert wird.

---

## 2. Messdaten

### 2.1 Batch-Modus (komplette Datei transkribieren)

| Datei | Audio (s) | STT (ms) | RTF | Text-Match |
|-------|-----------|----------|-----|------------|
| Testaufnahme4.m4a | 1.4 | 165 | 0.118 | NEIN (Gross/Klein) |
| TestAudio.m4a | 7.1 | 654-743 | 0.092-0.105 | — |
| Testaufnahme1.m4a | 8.5 | 604-627 | 0.071-0.074 | JA |
| Testaufnahme3.m4a | 10.0 | 0 | — | JA (Stille, VAD-Gate) |
| Testaufnahme5.m4a | 14.1 | 951-983 | 0.067-0.070 | NEIN |
| Testaufnahme2.m4a | 38.4 | 3302-3737 | 0.086-0.097 | NEIN |

### 2.2 Streaming-Modus (Segment-Transkription waehrend Aufnahme)

Alle Datenpunkte aus den Stream-Tests (de-Modus):

| Segment-Dauer (s) | STT (ms) | RTF | Kontext |
|--------------------|----------|-----|---------|
| 0.3 | 111 | 0.370 | Halluzinationsgefahr |
| 0.5 | 98 | 0.196 | Halluzinationsgefahr |
| 0.7 | 117 | 0.167 | Sinnentstellend |
| 0.8 | 147 | 0.184 | Sinnentstellend |
| 0.9 | 226 | 0.251 | Sinnentstellend |
| 1.4 | 165-285 | 0.118-0.204 | Grenzwertig |
| 1.9 | 255-306 | 0.134-0.161 | Grenzwertig |
| 2.1 | 300-332 | 0.143-0.158 | Akzeptabel |
| 2.4 | 305 | 0.127 | Akzeptabel |
| 2.9-3.2 | 303-307 | 0.095-0.106 | Akzeptabel |
| 3.5-3.9 | 373-428 | 0.098-0.110 | Gut |
| 4.4-5.0 | 359-416 | 0.082-0.083 | Gut |
| 5.6-5.8 | 426-539 | 0.076-0.093 | Gut |
| 7.1 | 654-743 | 0.092-0.105 | Gut |
| 8.5 | 604-627 | 0.071-0.074 | Sehr gut |
| 9.7 | 837 | 0.086 | Sehr gut |
| 12.0 | 944-963 | 0.079-0.080 | Sehr gut |
| 14.1 | 951-983 | 0.067-0.070 | Sehr gut |
| 38.4 | 3302-3737 | 0.086-0.097 | Beste |

### 2.3 Latenz-Modell

Aus den Datenpunkten ergibt sich:

```
STT_Zeit ≈ 130ms (Overhead) + 75ms × Audio_Sekunden
```

| Segment-Dauer | Erwartete STT | Unter 600ms? |
|---------------|---------------|--------------|
| 3s | ~355ms | Ja |
| 5s | ~505ms | Ja |
| 6s | ~580ms | Knapp ja |
| 7s | ~655ms | Nein |
| 8s | ~730ms | Nein |
| 10s | ~880ms | Nein |

---

## 3. Transkriptionsqualitaet

### 3.1 Qualitaet nach Segment-Laenge

| Segment-Laenge | Qualitaets-Bewertung | Typische Fehler |
|----------------|----------------------|-----------------|
| < 1s | **Unbrauchbar** | Halluzinationen ("Um." x223), Phantomwoerter |
| 1-3s | **Schlecht** | Sinnentstellend ("Op." statt "Ob", "Blitten", "Toppelte Vater") |
| 3-5s | **Akzeptabel** | Vereinzelte Fehler, Zusammenhang erkennbar |
| 5-8s | **Gut** | Natuerliche Saetze, gelegentliche Fehler bei Fachbegriffen |
| 8-12s | **Sehr gut** | Wenige Fehler, guter Kontext |
| 12s+ | **Beste** | Wie Batch-Qualitaet |

### 3.2 Bekannte Qualitaetsprobleme

**Nonsense-/Fachwörter:**
- "Hodenkompott" → "Hodenkompost" (leichte Variation)
- "Sockenkompott" → "Sockenkompost"
- "Zetafunktion" → "Zeta-Funktion" oder "Zetterfunktion"

**Englische Wörter im deutschen Text (de-Modus):**
- "Force Split" → "Forstblätter" oder "Forstblett"
- "Techstack" → "Textdeck"
- "whisprflow" → nicht erkannt

**Gross-/Kleinschreibung und Interpunktion:**
- "kurz" → "Kurz." (mit Grossbuchstabe und Punkt)
- Kommasetzung weicht vom erwarteten Text ab

**Halluzinationen bei kurzem Audio:**
- Segment < 1s mit Fuellwort "Um" → "Um." x223 Wiederholungen (5260ms!)
- Besonders kritisch im Auto-Modus

### 3.3 Sprach-Modi

| Modus | Deutsch-Qualitaet | Englisch | Code-Switching |
|-------|-------------------|----------|----------------|
| `de` | **Gut** | Schlecht (eindeutscht) | Nicht moeglich |
| `auto` | **Deutlich schlechter** | OK | Schlecht (Halluzinationen) |
| `en` | — | Gut | — |

**Empfehlung:** `de`-Modus verwenden. Englische Fachbegriffe ueber LLM Post-Processing korrigieren.

---

## 4. Streaming-Architektur

### 4.1 Grundprinzip

```
Audio-Thread (AVAudioEngine):
  → SampleBuffer.append()              [thread-safe, ~0ms]

Processing-Task (async, alle 100ms):
  → Neue Samples aus SampleBuffer lesen
  → StreamingVADProcessor.process()     [Silero VAD, <1ms]
  → Bei speechEnded:
      Falls Segment >= minSegmentDuration:
        → Qwen3ASR.transcribe()         [~300-600ms]
        → Text akkumulieren
      Sonst:
        → Mit naechstem Segment zusammenfassen
  → Bei Dauer > maxSegmentDuration:
      → Force-Split + transkribieren

User drueckt Stop:
  → VAD flush
  → Letztes Segment transkribieren
  → Latenz = STT des letzten Segments
```

### 4.2 Parameter (aktueller Stand)

| Parameter | Wert | Begruendung |
|-----------|------|-------------|
| `minSilenceDuration` | 0.4s | Kompromiss: Atempausen ignorieren, Sprechpausen erkennen |
| `minSegmentDuration` | 3.0s | Verhindert Mikro-Fragmente und Halluzinationen |
| `maxSegmentDuration` | 7.0s | Force-Split: STT ~655ms, gute Qualitaet |
| `onset` | 0.5 | Standard Silero |
| `offset` | 0.35 | Standard Silero |
| `minSpeechDuration` | 0.25s | Standard Silero |
| Context-Passing | Ja, fuer Segmente > 1s | Verbessert Zusammenhang zwischen Segmenten |

### 4.3 Probleme und Loesungen

| Problem | Ursache | Loesung |
|---------|---------|---------|
| Doppelte Texte nach Force-Split | VAD speechEnded deckt Force-Split-Bereich ab | `lastTranscribedEnd` Cursor |
| Halluzinationen bei < 1s Segmenten | Zu wenig Audio-Kontext fuer Modell | `minSegmentDuration` = 3s |
| Context-Halluzination | Langer Kontext + kurzes Audio → Modell wiederholt Kontext | Context nur bei Segmenten > 1s |
| Fragmentierte Saetze | Zu aggressive Segmentierung | `minSilenceDuration` 0.4s + `minSegmentDuration` 3s |
| Unnatuerlich lange Segmente bei fehlendem Pause | Kein Zwangs-Split | `maxSegmentDuration` = 7s |

---

## 5. Vergleich mit whisper.cpp

| Kriterium | whisper.cpp (large-v3-turbo) | Qwen3-ASR 0.6B |
|-----------|----------------------------|-----------------|
| RTF | ~0.35 | **~0.08** (4x schneller) |
| STT fuer 7s Audio | ~2400ms | **~650ms** |
| Modell laden | ~100ms (bereits geladen) | ~2800ms (kalt) |
| Deutsch-Qualitaet | Gut (6.3% WER CV) | Aehnlich (~6.5% WER FLEURS) |
| Streaming | Eigene VAD-Implementierung | speech-swift StreamingVADProcessor |
| Integration | CWhisper C-Bindings (stabil) | MLX-Swift (sehr neu, pre-1.0) |
| Metal Shaders | Nicht noetig | Manueller Build-Step erforderlich |

---

## 6. Vergleich mit Wispr Flow

Wispr Flow ist 100% Cloud-basiert mit ~700ms E2E-Latenz (ASR ~200ms + LLM ~200ms + Netzwerk ~300ms).

| Kriterium | Wispr Flow | DerFluisterer + Qwen3-ASR |
|-----------|-----------|---------------------------|
| ASR-Latenz | ~200ms (Cloud-GPU) | ~600ms (on-device, 7s Segment) |
| LLM Post-Processing | Ja (Llama, Cloud) | Noch nicht implementiert |
| Netzwerk-Overhead | ~300ms | **0ms** (on-device) |
| Gesamt E2E | ~700ms | ~600ms (Streaming) + LLM TBD |
| Privacy | Cloud (Screenshots!) | **100% on-device** |
| WER | ~10% (proprietaer) | ~6.5% (ohne LLM-Korrektur) |
| Code-Switching | Ja (100+ Sprachen) | Nein (de-Modus empfohlen) |

**Wispr Flow's Qualitaetsvorteil kommt primaer vom LLM Post-Processing**, nicht vom ASR-Modell.

---

## 7. Quantisierungs-Vergleich (4-bit vs 8-bit)

Getestet am 2026-04-08 mit `aufklarer/Qwen3-ASR-0.6B-MLX-8bit` (~1.2GB).

### Geschwindigkeit

| Datei | Audio | 4-bit STT | 8-bit STT | Faktor |
|-------|-------|-----------|-----------|--------|
| Testaufnahme4 | 1.4s | 165ms | 672ms | 4.1x langsamer |
| Testaufnahme1 | 8.5s | 604ms | 832ms | 1.4x langsamer |
| Testaufnahme5 | 14.1s | 951ms | 1430ms | 1.5x langsamer |
| Testaufnahme2 | 38.4s | 3302ms | 5864ms | 1.8x langsamer |

Durchschnittlich ~1.5x langsamer (nach Warmup). RTF steigt von 0.07-0.10 auf 0.10-0.15.

### Qualitaet

Kein messbarer Unterschied. Gleiche Fehler bei beiden Varianten:
- "Hodenkompost" (4-bit und 8-bit identisch)
- "Textdeck" statt "Techstack" (identisch)
- Match-Rate: 2/5 bei beiden

### Fazit

8-bit bringt keinen Qualitaetsgewinn bei ~50% hoeherer Latenz.
Die Quantisierung ist nicht der Qualitaets-Hebel — Kontext (Segment-Laenge) ist entscheidender.

Hinweis: MLX laeuft auf der GPU (Metal), nicht auf dem Neural Engine (ANE).
ANE wird nur von CoreML-Modellen genutzt (z.B. Silero VAD).

---

## 8. Offene Fragen

1. **LLM Post-Processing:** Wie stark verbessert ein lokales LLM (z.B. Llama 3.2 3B) die Transkriptionsqualitaet? Kann es "Forstblätter" → "Force Split" korrigieren?

2. **Groesseres Modell:** Qwen3-ASR 1.7B hat bessere WER (3.9% vs 6.5% FLEURS). Wie viel langsamer ist es? Passt es noch ins Latenz-Budget?

3. **Hybrid-Ansatz:** whisper.cpp + Qwen3-ASR parallel laufen lassen, Ergebnisse per LLM zusammenfuehren?

4. **Code-Switching:** Deutsch + Englisch gemischt transkribieren ohne Qualitaetsverlust im Deutschen?

5. **speech-swift Stabilitaet:** Framework ist pre-1.0 (branch: main). Wie stabil ist es fuer Produktion?

---

## 8. Empfehlung

### Fuer Prototyp → Produktion:

1. **Streaming mit Qwen3-ASR 0.6B ist vielversprechend** — Latenz-Ziel erreicht (56-95ms nach Stop)
2. **Qualitaet ist der Flaschenhals**, nicht die Geschwindigkeit
3. **LLM Post-Processing ist der naechste Hebel** — wie bei Wispr Flow
4. **`de`-Modus beibehalten**, englische Begriffe per LLM korrigieren
5. **speech-swift als Framework beobachten** — API koennte sich aendern

### Sweet-Spot Parameter:
- minSegmentDuration: 3s
- maxSegmentDuration: 7s
- minSilenceDuration: 0.4s
- Context-Passing: aktiviert
