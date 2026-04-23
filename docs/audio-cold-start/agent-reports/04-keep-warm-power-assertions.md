# Agent-Report 4 — macOS CoreAudio Warm-Keeping & Power Assertions

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Welche öffentlichen APIs oder Techniken erlauben es, das CoreAudio-Subsystem oder das Audio-Device im Power-Managed-State warm zu halten, OHNE permanent Audio auszugeben?

---

## 1. Gefundene Techniken (Pro/Con + Quellen)

| Technik | Was sie tut | Hält Audio-Device warm? | Pro | Con | Quelle |
|---|---|---|---|---|---|
| **`AudioDeviceStart` + Silence-IOProc** (HAL-level) | Dauerhaft laufender I/O-Callback mit stillen Frames | **Ja** — dokumentierter Effekt bei DACs/BT-Geräten | Direkter Weg auf HAL-Ebene; JUCE/SDL-Equivalent | Aktiver CPU-Takt (≈4096 fr/pass); `coreaudiod` setzt `PreventUserIdleSystemSleep`-Assertion ([Quelle](https://stuff-things.net/2017/05/10/sleepless-mac/)) | NVDA Issue [#5172](https://github.com/nvaccess/nvda/issues/5172), [#16148](https://github.com/nvaccess/nvda/issues/16148); [AudioKeepAlive](https://github.com/O-Brob/AudioKeepAlive) |
| **AVAudioEngine permanent gestartet** (kein stop()) | Engine läuft durch, Input-Tap bleibt installiert | **Ja** (indirekt via HAL) | Swift-freundlich, reduziert Engine-Restart-Kosten | AVAudioEngine-`start()` wird in Forum-Threads als teuer beschrieben; Empfehlung: "engine never stops" ([AVAudioPlayerNode delay thread](https://developer.apple.com/forums/thread/72866)) | [SO/Forums](https://developer.apple.com/forums/thread/72866) |
| **`kAudioHardwarePropertyPowerHint` = None** | Opt-out aus Power-Saving-Optimierungen | **Partiell** — verhindert nur Buffer-Size-Umschaltung von 512→4096 | Einzeiler, offizielle API | Keine Wirkung auf HW-D3-Sleep, nur auf Scheduler | [TN2321](https://developer.apple.com/library/archive/technotes/tn2321/_index.html) |
| **`IOPMAssertionCreateWithName`** (diverse Typen) | Verhindert System-/Display-Idle-Sleep | **Nein** — betrifft System-Sleep, nicht Audio-HW-Power-State | Simpel, offiziell | Greift erst bei globalem Idle-Sleep, nicht bei ~20s Audio-Idle | [IOPMAssertionTypes](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes), [cimgf](https://www.cimgf.com/2009/10/14/the-journey-to-disabling-sleep-with-iokit/) |
| **22kHz Inaudible-Sine-Output** | Permanenter Output von HF-Signal | **Ja** (empirisch bei DACs/BT) | Ausführlich dokumentiert für BT | Hörbar für junge Ohren/Fledermäuse, permanente DAC-Last, Nur Output | [AudioKeepAlive](https://github.com/O-Brob/AudioKeepAlive) |
| **Aggregate Devices / Hog Mode** | Exklusive Device-Lock | Unklar, kein Beleg für Warmhalten | — | Blockt andere Apps, nicht empfohlen | Keine positive Quelle gefunden |
| **Private HAL-Plugin / Kext** | — | — | — | SIP-blockiert, Notarization-Hürde | — |

## 2. Power-Assertion-Details — was `IOPMAssertionCreate` wirklich kann

Zitat aus [IOPMAssertionTypes / Apple Dev Forum](https://9to5answer.com/how-to-programmatically-prevent-a-mac-from-going-to-sleep):

> "`kIOPMAssertionTypeNoIdleSleep` will still allow the display to sleep, but the Mac never sleeps unless it runs out of battery power. Use cases […] 'computations that may not finish before the computer sleeps', such as bouncing a mixed audio/video file to disk."

**Wichtig**: Apple dokumentiert **keinen** Assertion-Typ, der HW-Power-State eines Audio-Chips direkt steuert. `PreventUserIdleSystemSleep` hält nur die CPU wach. Umgekehrter Pfad existiert: `coreaudiod` erzeugt **selbst** solche Assertions, wenn eine IOProc läuft ([Beispiel-Log](https://stuff-things.net/2017/05/10/sleepless-mac/)):
> `pid 237(coreaudiod): PreventUserIdleSystemSleep named: 'com.apple.audio.AppleHDAEngineOutput:1B,0,1,1:0.context.preventuseridlesleep'`

Das heißt: **IOProc-Lauf → Assertion gratis**, nicht umgekehrt.

## 3. WWDC / Apple-Doku-Funde

- **TN2321 "Saving Power During Audio I/O"** ([Link](https://developer.apple.com/library/archive/technotes/tn2321/_index.html)) — einzige offizielle Apple-Quelle zu Audio-Power: *"setting this hint will increase the default I/O buffer size from 512 sample frames to 4096 sample frames."* Steuert nur Buffer-Größe, **nicht** Device-HW-Sleep. Opt-out via `kAudioHardwarePowerHintNone`.
- **WWDC20 "Meet Audio Workgroups"** ([Link](https://developer.apple.com/videos/play/wwdc2020/10224/)) — Fokus auf Realtime-Thread-Scheduling auf Apple Silicon, nicht Device-Warmhalten.
- **Apple DTS (Kevin Elliott)** zu Input-Tap-Delay ([Thread 795429](https://developer.apple.com/forums/thread/795429)) bestätigt DTS-seitig: *"Do NOT manually activate audio sessions with setActive() once […] active"* und empfiehlt **Engine nicht neustarten**. Das ist die inoffizielle Bestätigung: "Engine laufen lassen" ist Apples empfohlener Weg.
- **Kein** WWDC-Talk adressiert explizit "Audio-Device warmhalten auf macOS". Keine Passage im Energy Efficiency Guide (archive), keine in IOKit PM Guide.

## 4. Was NICHT möglich ist (bewusst dokumentiert)

- **Kein** public API `kAudioDevicePropertyKeepAwake` oder Äquivalent. `kAudioHardwarePropertyPowerHint` ist das einzige Audio-Power-Property — und es geht in die **andere** Richtung (Power-Saving an).
- **Kein** `IOPMAssertion`-Typ zielt auf Audio-Hardware-D-States. Alle dokumentierten Typen wirken auf System/Display/CPU.
- **Kein** Callback-Äquivalent zu `CGDisplayRegisterReconfigurationCallback` für Audio-Power-State. `kAudioHardwarePropertyDevices` notifiziert nur bei Device-Wechsel, nicht bei Power-State-Transition.
- **Kein** Apple-Sample-Code, kein WWDC-Talk, kein DTS-Post beschreibt das Problem "~20s Cold-Start" namentlich. Apple-Haltung: Engine nicht stoppen → Problem existiert per Apple-Definition nicht.
- **Private Frameworks** (HALPlugin) sind nicht notarisierbar ohne Enterprise-Workaround.

**Pragmatische Empfehlung** (aus Summe der Quellen): AVAudioEngine dauerhaft `start()` halten mit installiertem Input-Tap; optional Output-Seite durch einen still-renderen `AVAudioPlayerNode` oder einen HAL-`AudioDeviceCreateIOProcID` mit Zero-Buffer versorgen. Das triggert automatisch `coreaudiod`'s eigene `PreventUserIdleSystemSleep`-Assertion und hält die gesamte Audio-Kette auf dem ~20s-Semi-Kalt-Timer oben. Kosten: ein paar Prozent CPU + kein Idle-Sleep während App läuft.

## Skepsis-Vermerk

- "20s Semi-Kalt" ist in keiner öffentlichen Apple-Quelle benannt. Die empirische Beobachtung muss auf unserer Seite verifiziert bleiben.
- Die Forum-/OSS-Hacks (22kHz, AudioKeepAlive) haben **keine** Latenz-Messungen, nur qualitative "works for me".
- Der Output-Pfad warmzuhalten via Silence ist **belegt** für BT/DAC. Für den **Input**-Pfad (Mikro) gibt es nur indirekte Belege via NVDA-Issue und AVAudioEngine-Forum-Konsens.

## Quellen

- [TN2321 — Saving Power During Audio I/O](https://developer.apple.com/library/archive/technotes/tn2321/_index.html)
- [IOPMAssertionTypes — Apple Dev Docs](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes)
- [kIOPMAssertionTypeNoDisplaySleep — Apple Dev Docs](https://developer.apple.com/documentation/iokit/kiopmassertiontypenodisplaysleep)
- [AudioDeviceStart — Apple Dev Docs](https://developer.apple.com/documentation/coreaudio/audiodevicestart(_:_:))
- [kAudioDevicePropertyIOCycleUsage — Apple Dev Docs](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyiocycleusage)
- [Meet Audio Workgroups — WWDC20 #10224](https://developer.apple.com/videos/play/wwdc2020/10224/)
- [Apple DTS — PTT Input Tap Delay Thread](https://developer.apple.com/forums/thread/795429)
- [AVAudioPlayerNode playback delay thread](https://developer.apple.com/forums/thread/72866)
- [AVAudioEngine excessive latency thread (unanswered)](https://developer.apple.com/forums/thread/705620)
- [Cocoa Is My Girlfriend — IOKit sleep assertion guide](https://www.cimgf.com/2009/10/14/the-journey-to-disabling-sleep-with-iokit/)
- [9to5answer — prevent Mac from sleeping](https://9to5answer.com/how-to-programmatically-prevent-a-mac-from-going-to-sleep)
- [Sleepless Mac — pmset assertions analysis](https://stuff-things.net/2017/05/10/sleepless-mac/)
- [Apple Community — coreaudiod keeping MBP awake](https://discussions.apple.com/thread/3349374)
- [NVDA Issue #5172 — keep audio device active](https://github.com/nvaccess/nvda/issues/5172)
- [NVDA Issue #16148 — play silence](https://github.com/nvaccess/nvda/issues/16148)
- [O-Brob/AudioKeepAlive — 22kHz sine technique](https://github.com/O-Brob/AudioKeepAlive)
- [TarnishedStella/keep-audio-alive](https://github.com/TarnishedStella/keep-audio-alive)
- [JUCE Forum — CoreAudio start/stop deadlock](https://forum.juce.com/t/coreaudio-deadlock-when-stopping-and-restarting-device/51882)
