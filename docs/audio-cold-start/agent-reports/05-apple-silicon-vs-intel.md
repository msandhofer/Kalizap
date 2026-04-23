# Agent-Report 5 — Apple Silicon vs. Intel: Audio Cold-Start

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Ist das Cold-Start-Verhalten Apple-Silicon-spezifisch (aggressives Power-Gating auf M-Chips), oder tritt es auch auf Intel-Macs in dieser Intensität auf?

---

**TL;DR:** Es gibt starke, aber primär community-basierte Belege, dass der Mikrofon-Cold-Start (2–5s) ein **Apple-Silicon-spezifisches Phänomen** ist (Hardware-Power-Gating mit ~30s Idle-Timeout). Für Audio-**Output** (NSSound) gibt es keinen eindeutigen Intel-vs-AS-Vergleich — hier ist die Quellenlage dünn und spekulativ.

---

## 1. Apple Silicon vs Intel — was ist dokumentiert

**Sichere Befunde (Mikrofon-Input, deckt unseren ~400ms AudioQueueStart-Fall):**

- `macos-mic-keepwarm` (drewburchfield, Feb 2026, Apple Feedback eingereicht) beschreibt das Symptom präzise: *"When no app is actively using the mic, macOS powers down the hardware, and the next capture start takes 2-5 seconds before audio samples arrive."* Das Tool zielt **explizit nur auf Apple Silicon (M1/M2/M3/M4)** — Intel wird nicht als betroffen genannt.
- Empirisch dokumentierter Idle-Timeout: *"If you use the mic again within ~30 seconds, it's instant. Wait a minute, and the delay is back."* Passt exakt zu unserer 20s-Beobachtung.
- Apple Community Thread 255596993: Nutzer vergleicht M3 Max/M1 Pro (Sonoma 14.4.1) mit 2019 Intel i5 (Ventura 13.3.1): *"45-50ms of uncompensated input delay"* auf AS vs. *"near real time"* auf Intel. Tenor der Antworten: *"I never had any problems with latency with the Intels before."*

**Unsicher / widersprüchlich (Steady-State-Latenz):**

- Blue Cat Audio Benchmark (professionelles Audio-Interface, keine Cold-Start-Messung): M1 **2.7ms** min-Latenz vs. Intel **3.2ms**. Also im **eingeschwungenen Zustand** ist AS besser — das widerspricht den Community-Reports nur scheinbar, weil die Reports fast alle Built-in-Mic-Szenarien sind.

**Spekulation:** Die Divergenz deutet darauf, dass das Power-Gating spezifisch am **internen Audio-DSP/Codec der M-SoCs** hängt, nicht an externen USB-/Thunderbolt-Interfaces. Nicht durch offizielle Doku belegt.

## 2. macOS-Versions-Timeline

- Big Sur (2020/2021, erste AS-Version) — Apple Community Thread 252764088 meldet erstmals deutlich höhere Core-Audio-Latenzen.
- Sonoma 14.x — Reports häufen sich.
- Sequoia 15.0 — allgemein langsamerer Boot, in 15.1 gefixt (unrelated aber zeitlich überlappend).
- Tahoe 26.2 — `mic-keepwarm` Autor testet dort, Problem weiter aktuell.
- **Kein CoreAudio-Release-Note** dokumentiert eine bewusste Power-Gating-Änderung. Unklar ob es mit M1-Einführung neu kam oder schrittweise aggressiver wurde.

## 3. Community-Wahrnehmung

- **SuperWhisper / WhisperFlow / Wispr Flow**-Community sieht genau unser Symptom — das ganze Tool-Ökosystem um Push-to-Talk-Warmup existiert, weil es auf AS ein echtes Problem ist.
- Etablierter Workaround: *"Keep the audio input stream open between recordings and use a ring buffer with lookback"* — genau der Keep-Warm-Pfad.
- **Kein offizielles Apple-Statement** gefunden. Feedback wurde eingereicht (Feb 2026), FB-ID nicht öffentlich.

## 4. Sichere vs. unsichere Befunde

| Befund | Belegt? |
|---|---|
| Mikrofon-Cold-Start 2–5s auf AS, ~30s Idle-Timeout | **Ja** (mehrere unabhängige Quellen, repro) |
| Intel Macs zeigen dieses Symptom **nicht** in dieser Intensität | **Mittel** — Community-Konsens + Tool-Scope, keine saubere Benchmark-Quelle die beides misst |
| Ursache = Hardware-Power-Gating des Audio-Subsystems | **Mittel** — vom Keep-Warm-Tool behauptet und plausibel, aber nicht von Apple dokumentiert |
| NSSound/Output-Cold-Start 1500ms ist ebenfalls AS-spezifisch | **Nein** — keine belegte Quelle zu NSSound-spezifischem Cold-Start. Vermutung: andere Ursache (Framework-Lazy-Load, AudioToolbox-Init), nicht Power-Gating. **Spekulation.** |
| macOS-Version-Regression mit konkretem Build | **Nein** — keine Release-Note, kein Bisect |

**Bottom line für das Design:** Für Input (400ms) ist die AS-Power-Gating-Hypothese gut gestützt → Keep-Warm-Stream ist der etablierte Fix. Für Output (1500ms NSSound) gibt es **keine belegte Quelle**, dass es AS-spezifisch ist — könnte genauso gut AudioToolbox-Framework-Lazy-Init sein, das auf Intel ähnlich wäre. Hier wäre ein eigener Test auf einem Intel-Mac der einzig saubere Weg.

## Quellen

- [macos-mic-keepwarm (GitHub)](https://github.com/drewburchfield/macos-mic-keepwarm)
- [Crazy high latency only on apple silicon (Apple Community)](https://discussions.apple.com/thread/255596993)
- [Apple M1 vs Intel for Audio Benchmark (Blue Cat Audio)](https://www.bluecataudio.com/Blog/behind-the-scenes/apple-m1-vs-intel-for-audio-a-benchmark/)
- [Unbelievable amount of recording latency (Apple Community)](https://discussions.apple.com/thread/255596376)
- [Big Sur Core Audio Latency Is Much Higher (Apple Community)](https://discussions.apple.com/thread/252764088)
- [FIX: sustained coreaudiod CPU usage on M1 (MacRumors)](https://forums.macrumors.com/threads/fix-sustained-12-15-coreaudiod-cpu-usage-on-m1-possibly-intel-too.2331498/)
- [0.3 sec audio latency on M1 VMs (Apple Developer Forums)](https://developer.apple.com/forums/thread/693897)
- [AVAudioPlayerNode play() execution time proportional to buffer (Apple Developer Forums)](https://developer.apple.com/forums/thread/72866)
- [AVAudioEngine player node excessive delay (Apple Developer Forums)](https://developer.apple.com/forums/thread/705620)
- [Wispr Flow Troubleshooting mic issues](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues)
