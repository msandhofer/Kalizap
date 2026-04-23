# Audio Cold-Start auf macOS — Analyse, Research und Entscheidung (Stand 2026-04-22)

Dokumentation des Audio-Cold-Start-Problems auf macOS (Apple Silicon), der Recherche-Ergebnisse und der gewählten Lösung für DerFlüsterer (Issue #42 — *Spectrum-Overlay erscheint beim ersten Diktat ~2s verzögert*).

**Referenz-Reports:** Detailierte Agent-Recherche-Ergebnisse mit Quellen in [`agent-reports/`](./agent-reports/).

---

## TL;DR

- **Beim ersten Hotkey-Press nach App-Start** dauert es auf Apple Silicon **~1.9 Sekunden**, bis Overlay + Sound erscheinen. Ursache: zwei sequentielle Audio-Cold-Starts in `handleStart` — Output (`NSSound.play`, ~1479 ms) und Input (`AudioQueueStart`, ~400 ms).
- **Nach ~20 Sekunden Inaktivität** werden beide Audio-Subsysteme wieder „semi-kalt" (~300 ms pro Pfad).
- **Root Cause:** macOS betreibt aggressives Hardware-Power-Gating auf M-Chips. Apple dokumentiert keinen Idle-Timeout und bietet keine Public-API zum Warmhalten.
- **Die einzige belegte vollständige Lösung** (Input-Stream permanent offen halten) würde den orangen Mikrofon-Indikator dauerhaft aktiv lassen. Das haben wir als UX-Dealbreaker abgelehnt.
- **Unsere Lösung (Plan A):** Output-Cold-Start mildern via System-Audio-Activity-Snapshot (Sound skippen wenn System kalt, stummen Ping in Hintergrund zum Warmhalten). Input-Cold-Start akzeptieren. Framework-Lazy-Init beim App-Start vorziehen, um die einmaligen 500–1000 ms beim ersten Press zu sparen.

---

## 1. Empirische Messungen (eigene Logs, 2026-04-22)

Instrumentierung in `DictationPipeline.handleStart`, `AudioQueueAdapter.startCapture`, `SpectrumOverlayWindow.show`. Verbose-Logging via `--verbose-log` in `/var/folders/…/T/derfluesterer-debug.log`.

| Lauf | Szenario | `handleStart` TOTAL | `playStartSound` | `recorder.startRecording` | `overlay.show` | First spectrumBands |
|------|---|---|---|---|---|---|
| **1** | **Kaltstart** (erster Press nach App-Launch) | **1896 ms** | **1479 ms** | **400 ms** | 12 ms | 1974 ms |
| 2 | Warm (direkt danach) | 100 ms | 22 ms | 65 ms | 6 ms | 175 ms |
| 3 | Warm | 101 ms | 19 ms | 64 ms | 11 ms | 184 ms |
| 4 | Warm | 90 ms | 19 ms | 58 ms | 6 ms | 173 ms |
| 5 | Warm | 91 ms | 14 ms | 60 ms | 11 ms | 167 ms |
| **6** | **Semi-kalt** (nach 21 s Pause) | **631 ms** | **314 ms** | **305 ms** | 7 ms | 737 ms |
| 7 | Warm (direkt nach Lauf 6) | 100 ms | 25 ms | 61 ms | 8 ms | 185 ms |

**Weitere Messwerte:**
- `DeepFilterNet3` Load beim App-Start: **285 ms**, passiert asynchron, ist beim ersten Hotkey-Press bereits fertig.
- `AudioQueueNewInput` + `AudioQueueAllocateBuffer` + `AudioQueueEnqueueBuffer` zusammen: < 1 ms. Die gesamten 400 ms von `startCapture` entfallen auf `AudioQueueStart`.
- Erster AudioQueue-Buffer-Callback nach `startCapture`: Kalt **480 ms**, warm **~140 ms**.

**Test-Hardware:** Apple Silicon (MacBook).

## 2. Root-Cause-Analyse

### Zwei unabhängige Audio-Pfade

```
                       coreaudiod (System-Daemon)
                              /        \
             Input-HAL-Pfad  /          \  Output-HAL-Pfad
                            /            \
                   Default Input Device   Default Output Device
                   (Built-in Mic)         (Built-in Speaker)
                   Audio-DSP (M-Chip)     DAC + Codec-Chip
                   own Power-Gating       own Power-Gating
```

Input (Mikrofon) und Output (Lautsprecher) sind technisch unabhängig: eigene `AudioDeviceID`, eigene Power-States, eigene HAL-Pfade. Beide durchlaufen aber denselben System-Daemon `coreaudiod` und teilen sich einmaligen Framework-Init pro App-Prozess.

### Warum 1500 ms beim ersten Press, 300 ms nach Pause

Der Erst-Press-Wert setzt sich zusammen aus:
1. **Framework Lazy-Init** (AudioToolbox, NSSound, IPC zu coreaudiod) — einmalig pro App-Prozess, Schätzung 500–1000 ms.
2. **HW-Wake-Up des Audio-DACs** (Power-Gating) — Schätzung 300–500 ms.

Nach dem ersten Press bleibt das Framework warm; nur der HW-Wake-Up kommt nach Pause wieder.

### Warum YouTube das Problem teilweise kaschiert

Wenn ein anderer Prozess (Spotify, YouTube) Audio ausgibt, bleibt der **Output-HW-Pfad** warm. Der nächste `NSSound.play()` kommt sofort. Der **Input-Pfad** (Mikrofon) ist davon aber nicht betroffen, weil ein separater Device mit eigenem Power-Gating. Dies erklärt den empirischen Eindruck „mit YouTube ist der Sound sofort da" bei gleichzeitig weiter langsam startendem Recorder.

### Das ist Apple-Silicon-spezifisch

Community-Quellen ([macos-mic-keepwarm](https://github.com/drewburchfield/macos-mic-keepwarm), [Apple Community 255596993](https://discussions.apple.com/thread/255596993)) zeigen: Intel-Macs haben das Symptom in dieser Intensität nicht. Die M-Chips praktizieren aggressiveres Power-Gating des internen Audio-DSP. Nicht durch Apple offiziell dokumentiert, aber durchgehend in der Community bestätigt.

## 3. Recherchierte Lösungswege

Sechs parallele Agent-Recherchen haben verschiedene Lösungsrichtungen untersucht. Gesammelte Erkenntnisse:

### 3.1 Stream-offen-halten (Keep-Warm) — *die belegte wirksame Lösung*

**Mechanismus:** `AVCaptureSession` + `AVCaptureAudioDataOutput` dauerhaft laufen lassen, Samples verwerfen. Beim Hotkey nur ins Aufnahme-Routing umleiten.

**Pro:** Beseitigt den Cold-Start vollständig (Input-Pfad bleibt aktiv → coreaudiod setzt automatisch `PreventUserIdleSystemSleep`-Assertion → HW-DSP bleibt wach).

**Con:** Orange Mikrofon-Indikator dauerhaft in der Menubar. Apple erlaubt kein Ausblenden auf dem Main Display ([Apple Support 118449](https://support.apple.com/en-us/118449)).

**Real-world Usage:** `macos-mic-keepwarm` (externer LaunchAgent), angeblich auch SuperWhisper/WhisperFlow/Wispr Flow intern. Keine Open-Source-Voice-App hält den Stream selbst offen — alle nutzen Push-to-Talk on demand und zahlen den Cold-Start.

### 3.2 Ring-Buffer mit Lookback

**Mechanismus:** Zusätzlich zu Keep-Warm wird die Audio-Historie in einem Ring-Buffer gehalten. Bei Hotkey wird auch „Audio von vor dem Keydown" mitgenommen.

**Technisch trivial:** TPCircularBuffer (MIT-lizenziert, Standard der CoreAudio-Community), 10 s @ 16 kHz mono = ~320 KB RAM.

**Identischer UX-Tradeoff** wie Keep-Warm (orange Dot).

**Nirgendwo belegt in Voice-to-Text-Apps auf macOS** — nur im Video-Bereich (GoPro, Tesla Dashcam, Milestone XProtect).

### 3.3 AVAudioEngine permanent gestartet (DAW-Pattern)

**Mechanismus:** `AVAudioEngine().prepare().start()` beim App-Start, nie stoppen. Silence-Rendering durch leeren Node-Graph. Hält HAL-IO-Thread aktiv.

**Pro:** Gleicher Effekt wie Keep-Warm, aber semantisch „App hat Audio-Context aktiv", nicht „App verwendet Mikrofon".

**Con:** Mozilla Firefox-Messung zeigt **0.8 % CPU dauerhaft**; Energie-Impact messbar (10–15 min Akku-Reduktion pro 8 h für Menubar-Helper). Nicht offiziell dokumentiert ob es den Mic-Indikator unterdrückt (vermutlich nicht, wenn `inputNode` verwendet wird).

**DAW-Standard:** Ableton, Logic, Audio Hijack machen es so. Für Voice-to-Text-Menubar-App Overkill.

### 3.4 Power-Assertions (`IOPMAssertionCreate`)

**Apple dokumentiert keinen Assertion-Typ, der den HW-Power-State eines Audio-Chips steuert.** Existierende Typen (`kIOPMAssertPreventUserIdleSystemSleep`, `NoIdleSleep`, `NoDisplaySleep`) wirken nur auf System-/Display-/CPU-Sleep.

**Umgekehrter Pfad existiert:** Eine laufende AudioUnit-IOProc erzeugt automatisch eine PowerAssertion — aber das hilft nur als Nebeneffekt einer der anderen Techniken.

### 3.5 API-Wechsel (AudioQueue → AVAudioEngine / AUHAL / SCStream)

**Alle getesteten APIs nutzen intern denselben HAL-Pfad.** `AVAudioInputNode` wrappt `kAudioUnitSubType_HALOutput` ([Apple DTS Forum 71008](https://developer.apple.com/forums/thread/71008)). Der Cold-Start liegt nicht in der API-Schicht, sondern im HAL/coreaudiod.

**Einzige potenzielle Ausnahme:** `AUAudioUnit.startHardware()` direkt — eine anekdotische Behauptung „latency decreased" in einem Medium-Artikel, aber ohne Zahlen. Nicht belastbar.

**Fazit:** API-Wechsel bringt nichts Substanzielles für den Cold-Start.

### 3.6 Framework Lazy-Init vorziehen

**Mechanismus:** `NSSound(named: "Tink")` einmal beim App-Start instantiieren (ohne `.play()`). Das lädt AudioToolbox + initialisiert die NSSound-Klassenhierarchie, wärmt aber die Hardware **nicht** auf.

**Pro:** Einmalig beim App-Start, einmal bezahlt für den ganzen Prozess-Lebenszyklus. Spart im ersten echten Press ~500–1000 ms.

**Con:** Mini-Verzögerung beim App-Start (wird hinter dem Model-Loading versteckt).

**Nebeneffekt:** Betrifft nur den einmaligen Framework-Init, nicht den wiederkehrenden HW-Wake-Up nach Idle.

### 3.7 Prewarm-at-init mit `inputFormat`-Abfrage (Recap-Pattern)

**Recap** ([GitHub](https://github.com/RecapAI/Recap/blob/main/Recap/Audio/Capture/MicrophoneCapture.swift)) zeigt einen Kompromiss: Bei `init()` wird im Hintergrund der AudioEngine-Node-Graph vorbereitet und `inputNode.inputFormat(forBus: 0)` abgefragt (tippt die Hardware an). `engine.start()` bleibt aber on-demand. Spart ~100 ms, nicht aber den echten HW-Wake-Up.

## 4. Unsere Entscheidung: Plan A

**Gewählt:** Output-Cold-Start gezielt mildern + Framework-Lazy-Init vorziehen. Input-Cold-Start akzeptieren.

**Abgelehnt:**
- **Permanente Audio-Engine / Stream-offen-halten** — orange Mic-Indicator dauerhaft wäre UX-Dealbreaker. Vertrauensfrage, auch für potentielle spätere Nutzer.
- **Ring-Buffer mit Lookback** — identisch mit obigem, plus zusätzliche Komplexität ohne zusätzlichen Nutzen für Push-to-Talk-Szenarien.
- **API-Wechsel AudioQueue → AVAudioEngine** — bringt substantiell nichts, siehe 3.5.
- **Periodischer Keep-Alive-Ping (stumm alle 10/30 s)** — behindert System-Power-Management, nicht sinnvoll für Akku-Laufzeit.

### Umsetzungs-Details

1. **Neue Klasse `SystemAudioActivityMonitor`** (in `DerFluisterer/Services/`):
   - Protocol `AudioActivityMonitoring` mit `isAudioWarm() -> Bool`
   - **Listener-basiert** via `AudioObjectAddPropertyListenerBlock` auf `kAudioDevicePropertyDeviceIsRunningSomewhere` des Default Output Device
   - Interner `AudioActivityState` (pure struct, testbar) pflegt:
     - `isCurrentlyRunning` (aus Property-Snapshot)
     - `lastActivityAt` (Zeitstempel der letzten running→stopped-Transition)
   - `isAudioWarm()` = currently running **ODER** letzter running-Moment innerhalb Warmth-Window (Default 5 s)
   - Deckt zwei Szenarien ab:
     - Fremde Audio-Aktivität (YouTube/Spotify): Listener registriert deren Start/Stop → 5 s Puffer
     - Eigener Prewarm: unser stummer Ping triggert ebenfalls running→stopped-Transition

2. **`SoundBackend.prewarm()` erweitern:**
   - Protokoll-Methode + `SystemSoundBackend.prewarm()` mit `NSSound(named: "Tink").volume = 0` + `.play()`
   - `SoundPlaying` um `prewarm() async` erweitern
   - Triggert einen vollen Output-Pfad-Wake-Up, ohne dass der User etwas hört

3. **`DictationPipeline.handleStart` — Audio-Activity-Check:**
   ```swift
   if deps.audioMonitor.isAudioRunningSomewhere() {
       await deps.sound.playStartSound()
   } else {
       FileLog.log("handleStart — audio cold, skip sound + prime in background")
       Task.detached { await deps.sound.prewarm() }
   }
   ```

4. **Framework Lazy-Init beim App-Start:**
   - In `PipelineFactory.makePipeline`: einmal `_ = NSSound(named: "Tink")` — triggert AudioToolbox-Load, ohne HW zu wecken
   - Log-Eintrag zur Verifikation

5. **Instrumentierung bleibt drin** (TIMING-Logs in `handleStart`, `AudioQueueAdapter`, `SpectrumOverlayWindow`) für spätere Regression-Checks.

### Verhalten nach Plan A

| Szenario | Sound | Overlay-Verzögerung |
|---|---|---|
| Warm (Spotify/YouTube läuft oder lief gerade) | Spielt sofort (~20 ms) | ~100 ms (Recorder warm) |
| Cold (erster Press nach App-Launch) | Kein Sound, stummer Ping im Hintergrund | ~400 ms (Recorder kalt) |
| Cold (nach >20 s Pause) | Kein Sound, stummer Ping im Hintergrund | ~300 ms (Recorder semi-kalt) |

Framework-Lazy-Init sorgt dafür, dass der allererste Press nach App-Launch nicht zusätzlich 500–1000 ms durch Framework-Loading verzögert wird.

## 5. Offene Themen

**Nicht gelöst (bewusst akzeptiert):**
- **Input-Cold-Start (Mikrofon-HW-Wake-Up)** — ~400 ms beim ersten Press nach App-Launch, ~300 ms nach langer Pause. Lösung wäre Keep-Warm-Stream → orange Dot. Abgelehnt.
- **Bluetooth-Device-Switch-Latenz** — 1–3 s zusätzlich beim Wechsel zwischen BT-Geräten (SCO-Negotiation). Kein Fix ohne Apple-API.

**Zukünftige Überlegungen:**
- Wenn Apple auf [FB21969131](https://github.com/drewburchfield/macos-mic-keepwarm/blob/main/APPLE_FEEDBACK.md) (Feb 2026, Drew Burchfield) reagiert und z.B. eine `prepareForCapture()`-API liefert, sollte diese Dokumentation revisited werden.
- Falls ein UX-Test zeigt, dass 400 ms Overlay-Verzögerung dennoch störend sind: Evaluation, ob ein optionaler „Responsive Mode"-Setting (permanent Mic offen, orange Dot sichtbar) angeboten werden soll.

## 6. Quellen-Übersicht

### Primärquellen (häufig zitiert)

- **[macos-mic-keepwarm (Drew Burchfield)](https://github.com/drewburchfield/macos-mic-keepwarm)** — Referenz-Hack, dokumentiert Problem und Lösung präzise. Feedback an Apple Feb 2026.
- **[Apple DevForum Thread 795429](https://developer.apple.com/forums/thread/795429)** — Apple DTS bestätigt: Cold-Start liegt an `callservicesd`-Audio-Release.
- **[Apple DevForum Thread 71008](https://developer.apple.com/forums/thread/71008)** — Apple DTS: `AVAudioInputNode` wrappt `kAudioUnitSubType_HALOutput`.
- **[AudioHardware.h Header (phracker SDK mirror)](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.9.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardware.h)** — Semantik von `kAudioDevicePropertyDeviceIsRunningSomewhere`.
- **[Apple Support 118449](https://support.apple.com/en-us/118449)** — Mikrofon-Indikator kann nur auf *externen* Displays ausgeblendet werden.

### Open-Source-Apps (Code-Referenz)

- [pindrop](https://github.com/watzon/pindrop) — AVAudioEngine, on-demand, kein Prewarm.
- [Recap](https://github.com/RecapAI/Recap) — einzige mit Node-Graph-Prewarm bei init.
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Library-Ebene, on-demand.
- [AudioWhisper](https://github.com/mazdak/AudioWhisper) — AVAudioRecorder (File-based).

### Ergänzende Quellen

- [Handling audio capture gaps on macOS (Nonstrict)](https://nonstrict.eu/blog/2024/handling-audio-capture-gaps-on-macos/)
- [TN2321 — Saving Power During Audio I/O](https://developer.apple.com/library/archive/technotes/tn2321/_index.html)
- [mikeash — Why CoreAudio is Hard](https://www.mikeash.com/pyblog/why-coreaudio-is-hard.html)
- [A Tasty Pixel — Circular ring buffer](https://atastypixel.com/circular-ring-buffer-plus-neat-virtual-memory-mapping-trick/)
- [Apple Community 255596993 — Crazy high latency only on apple silicon](https://discussions.apple.com/thread/255596993)
- [Bugzilla 1220378 — AVAudioEngine keeps running (0.8 % CPU)](https://bugzilla.mozilla.org/show_bug.cgi?id=1220378)
- [supermegaultragroovy — It's over, AVAudioEngine](https://supermegaultragroovy.com/2021/01/26/it-s-over-avaudioengine/)
- [Wispr Flow — Technical challenges](https://wisprflow.ai/post/technical-challenges)
- [SuperWhisper Changelog](https://superwhisper.com/changelog)

**Vollständige Quellenlisten pro Thema in:**
- [`agent-reports/01-voice-apps-startup-patterns.md`](./agent-reports/01-voice-apps-startup-patterns.md)
- [`agent-reports/02-audio-api-stack-comparison.md`](./agent-reports/02-audio-api-stack-comparison.md)
- [`agent-reports/03-ring-buffer-lookback.md`](./agent-reports/03-ring-buffer-lookback.md)
- [`agent-reports/04-keep-warm-power-assertions.md`](./agent-reports/04-keep-warm-power-assertions.md)
- [`agent-reports/05-apple-silicon-vs-intel.md`](./agent-reports/05-apple-silicon-vs-intel.md)
- [`agent-reports/06-open-source-app-source-analysis.md`](./agent-reports/06-open-source-app-source-analysis.md)

---

## Änderungsverlauf

- **2026-04-22** — Initiale Recherche, Messungen, Plan-A-Entscheidung (Issue #42).
- **2026-04-23** — Nachjustierung nach erster Messung: Plan A mit reinem Snapshot erkannte den Zustand nach YouTube-Stop + ~1 s Wartezeit als „cold", weil der HAL-Lag in der Praxis kürzer ist als <1 s (Forum-Schätzung 1–2 s war zu optimistisch). Nachgezogen: `SystemAudioActivityMonitor` wurde von Snapshot auf **Listener + Timestamp mit 5-Sekunden-Warmth-Window** umgestellt. `AudioActivityState`-State-Machine extrahiert für Testbarkeit. Deckt sowohl Prewarm-Effekt als auch fremde Audio-Aktivität ab.
