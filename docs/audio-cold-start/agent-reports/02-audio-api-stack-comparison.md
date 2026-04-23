# Agent-Report 2 — macOS Audio-Capture-API-Stack Vergleich

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Welcher macOS Audio-Capture-API-Stack hat den geringsten Cold-Start-Overhead? Vergleich von AudioQueue, AVAudioEngine, AudioUnit direkt, SCStream/ScreenCaptureKit, CoreAudio HAL direkt, AVCaptureSession.

---

**Skeptischer Hinweis vorweg:** Es gibt **keine einzige publizierte Benchmark-Suite**, die alle gelisteten APIs nebeneinander mit Cold-Start-Millisekunden misst. Die folgenden Zahlen stammen aus (a) einem spezifischen Bug-Report an Apple (FB21969131) mit Messungen, (b) Apple DTS-Aussagen ohne Zahlen, (c) anekdotischen Entwickleraussagen, (d) Source-Code produktiver Dictation-Apps. Jede Zahl unter 100 ms in der Tabelle ist **extrapoliert aus Code-Verhalten/Apple-DTS-Framing**, nicht aus einem echten Benchmark-Paper.

## 1. API-Vergleich

| API | Cold-Start (publiziert) | Swift | Besonderheiten | Quellen |
|---|---|---|---|---|
| **AudioQueue** | unser eigener Messwert 400ms; keine öffentliche Messung | OK (C-Bridge) | High-Level, legacy, interne Pipeline identisch zu AUHAL+AudioConverter | unser Messwert; [Apple DTS auf PTT-Thread](https://developer.apple.com/forums/thread/795429) charakterisiert Delay als "callservicesd releasing audio input … roughly the same as unmuting a CallKit call" |
| **AVAudioEngine** | keine Zahl, aber dokumentiert als "smushing" + 16 kHz-Downgrade bei AirPods; **wrapped kAudioUnitSubType_HALOutput intern** | nativ | `outputNode`/`mainMixerNode`-Zugriff triggert Aggregate-Device-Erstellung → zusätzliche Setup-Arbeit; `inputNode.auAudioUnit` gibt Low-Level-Zugriff | [supermegaultragroovy "It's over"](https://supermegaultragroovy.com/2021/01/26/it-s-over-avaudioengine/); [Apple DTS forum](https://developer.apple.com/forums/thread/71008): "AVAudioInputNode does wrap the kAudioUnitSubType_HALOutput" |
| **AudioUnit direkt (AUHAL)** | qualitativ "latency decreased" vs AVAudioEngine, **keine Zahl** | C-Bridge | `startHardware()`/`AudioOutputUnitStart` — was AVAudioEngine intern aufruft, nur ohne Graph-Wrapping | [Itsuki Medium](https://levelup.gitconnected.com/swift-audio-capturing-the-absolute-limit-of-avaudioengine-time-for-hal-audiounit-91ee6b53db41): "Are we going to have more latency … Actually, NO! The latency even decreased" — **ohne Zahl, skeptisch behandeln** |
| **CoreAudio HAL (`AudioDeviceCreateIOProcID` + `AudioDeviceStart`)** | keine Zahl; tiefste öffentliche Schicht | C-Bridge | Produktiv in Pindrop für System-Audio-Tap eingesetzt | [pindrop AudioRecorder.swift:523,541](https://github.com/watzon/pindrop/blob/main/Pindrop/Services/AudioRecorder.swift) |
| **AVCaptureSession (`AVCaptureAudioDataOutput`)** | `startRunning()` ist "blocking … can take a long time" → Background-Queue empfohlen | nativ | Als **Keep-Warm**-Vehikel produktiv verwendet, da es "den Mic-Stream offen hält" und Hardware-Sleep verhindert | [Apple Docs AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession); [mic-keepwarm main.swift](https://github.com/drewburchfield/macos-mic-keepwarm/blob/main/Sources/MicWarm/main.swift) |
| **ScreenCaptureKit (SCStream + Microphone)** | keine publizierten Zahlen; Mic-Support erst macOS 15 | nativ | HW-beschleunigt; TCC-Mikrofon-Consent identisch | [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/); [creavit.studio guide](https://creavit.studio/blog/screencapturekit-audio-recording-mac-guide) |
| **Private / neuere APIs** | nichts öffentlich aufgetaucht | — | Apple hat auf FB21969131 noch nicht geantwortet; `prepareForCapture()`-API-Request liegt vor | [mic-keepwarm APPLE_FEEDBACK.md](https://github.com/drewburchfield/macos-mic-keepwarm/blob/main/APPLE_FEEDBACK.md) |

## 2. Erkenntnisse

- **Unsere 400 ms sind kein AudioQueue-Bug, sondern ein System-Verhalten**, das sich API-übergreifend manifestiert. Drew Burchfields Feedback-Report an Apple ([FB21969131, Feb 2026](https://github.com/drewburchfield/macos-mic-keepwarm/blob/main/APPLE_FEEDBACK.md)) misst **2–5 Sekunden Cold-Start auf Apple Silicon** wenn der Mic ~30–60 s idle war, plus **1–3 s für Bluetooth-SCO-Negotiation**. Apple DTS bestätigt die Delay-Quelle: `callservicesd`-Audio-Release. Der Engpass ist Power-Management + coreaudiod-Pipeline, nicht dein API-Aufruf.
- **AVAudioEngine wrappt intern AUHAL** ([DTS-Aussage](https://developer.apple.com/forums/thread/71008)). Ein Wechsel AudioQueue → AVAudioEngine ändert daher am Cold-Start sehr wahrscheinlich **nichts Substanzielles** — er bringt sogar neue Fallen (AirPods-16-kHz-Downgrade, Aggregate-Device-Auto-Creation).
- **Der einzige belegte wirksame Workaround** ist Keep-Warm: Mic-Stream permanent offen halten, Samples verwerfen. In Produktion (mic-keepwarm, SuperWhisper, WhisperFlow laut README) via `AVCaptureSession + AVCaptureAudioDataOutput`. Nicht weil diese API "schneller startet", sondern weil sie robust offen bleibt und Bluetooth-Deadlocks handhabbar sind (siehe Kommentare `main.swift:207-235` zum CMIO-Semaphore-Deadlock).
- **AUHAL direkt** (via `AUAudioUnit` mit `kAudioUnitSubType_HALOutput` → `startHardware()`) ist die kürzeste Code-Kette, aber die Itsuki-Behauptung "latency decreased" ist unquantifiziert — skeptisch behandeln.
- **AVCaptureSession.startRunning()** blockiert ebenfalls; Apple empfiehlt explizit Background-Queue. Kein "schneller als AudioQueue"-Beleg.
- **ScreenCaptureKit** für Mic-Capture: null Latenz-Benchmarks öffentlich; keine Hinweise auf Cold-Start-Vorteil, identischer TCC-Pfad.

**Empfehlung (mit Vorbehalt):** Wenn 400 ms dein kritischer Pfad ist, wechsle **nicht die API** — wechsle die **Strategie**: Keep-Warm-Stream via `AVCaptureSession`/`AUHAL` parallel offen halten (orange Mic-Indicator akzeptieren oder privacy-toggle anbieten) und beim Hotkey nur das Routing in deinen Transcription-Buffer aktivieren. Das bringt deine gemessenen 60 ms Warm-Start überall hin.

## 3. Open Questions

- Ob `startHardware()` auf `AUAudioUnit` wirklich schneller ist als `AudioQueueStart` — **kein reproduzierbarer Benchmark gefunden**, müsste selbst gemessen werden.
- Ob ScreenCaptureKit's Mic-Pfad (macOS 15+) ein günstigeres Power-Management-Verhalten hat — keine Daten.
- Ob `kAudioDevicePropertyDeviceIsRunningSomewhere == 1` durch einen Fremdprozess (z. B. Voice-Control, `coreaudiod` selbst) das Power-State umgeht — Drews Report deutet "nein, nur aktive Capture hält es wach" an, aber nicht sauber isoliert verifiziert.
- Unser konkreter 400 ms-Wert: liegt bei erster Aktivierung nach App-Launch, bei idle >30 s, oder generell bei erster Aktivierung pro Prozess? Die Drew-Report-Zahlen suggerieren es ist Idle-abhängig.
- Ob Apple auf FB21969131 antwortet / eine `prepareForCapture()`-API landet — Report ist Feb 2026, **noch keine Response** laut Repo.

## Quellen

- [AudioEngineLoopbackLatencyTest (jnpdx)](https://github.com/jnpdx/AudioEngineLoopbackLatencyTest)
- [Apple DevForum — "Delay in Microphone Input When Talking"](https://developer.apple.com/forums/thread/795429)
- [Apple DevForum — "Select the audio device for AVAudioEngine"](https://developer.apple.com/forums/thread/71008)
- [supermegaultragroovy — "It's over, AVAudioEngine"](https://supermegaultragroovy.com/2021/01/26/it-s-over-avaudioengine/)
- [supermegaultragroovy — "More on AVAudioEngine + AirPods"](https://supermegaultragroovy.com/2021/01/28/more-on-avaudioengine-airpods/)
- [Itsuki Medium — "Absolute Limit of AVAudioEngine"](https://levelup.gitconnected.com/swift-audio-capturing-the-absolute-limit-of-avaudioengine-time-for-hal-audiounit-91ee6b53db41)
- [macos-mic-keepwarm (drewburchfield)](https://github.com/drewburchfield/macos-mic-keepwarm)
- [mic-keepwarm APPLE_FEEDBACK.md](https://github.com/drewburchfield/macos-mic-keepwarm/blob/main/APPLE_FEEDBACK.md)
- [pindrop AudioRecorder.swift (watzon)](https://github.com/watzon/pindrop)
- [mikeash — "Why CoreAudio is Hard"](https://www.mikeash.com/pyblog/why-coreaudio-is-hard.html)
- [Apple TN2091 — HAL Output Audio Unit für Input](https://developer.apple.com/library/archive/technotes/tn2091/_index.html)
- [Apple Docs — AudioOutputUnitStart](https://developer.apple.com/documentation/audiotoolbox/1439763-audiooutputunitstart)
- [Apple Docs — AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- [Apple Docs — ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/)
- [ScreenCaptureKit Audio Guide (creavit.studio)](https://creavit.studio/blog/screencapturekit-audio-recording-mac-guide)
- [atastypixel — Using RemoteIO](https://atastypixel.com/using-remoteio-audio-unit/)
