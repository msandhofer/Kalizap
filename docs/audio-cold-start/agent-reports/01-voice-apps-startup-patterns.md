# Agent-Report 1 — Voice-Apps auf macOS: Startup-Patterns

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Wie machen macOS-Apps, die auf Sprache reagieren (Dictation, Siri, Teams, Zoom, Meet, Discord, Loom, Descript), den Übergang "User drückt Aufnahme-Button" → "Audio wird tatsächlich aufgezeichnet" schnell und unmerklich?

---

## 1. Gefundene Patterns (mit Zitaten)

### Pattern A — Mic permanent warmhalten (dominierender Ansatz)
Drew Burchfields **macos-mic-keepwarm** dokumentiert das Problem präzise und zeigt die Root-Cause-Analyse:

> "When no app is actively using the mic, macOS powers down the hardware. The next capture start takes 2-5 seconds before audio samples arrive. If you use the mic again within ~30 seconds, it's instant. Wait a minute, and the delay is back." ([github.com/drewburchfield/macos-mic-keepwarm](https://github.com/drewburchfield/macos-mic-keepwarm))

Der Fix nutzt `AVCaptureSession` (nicht `AVAudioEngine`), hält den Stream offen und verwirft die Samples:

> "mic-warm uses AVCaptureSession with an audio data output to hold the default microphone open. Audio samples are captured and immediately discarded."

Bluetooth-Switching ist ein zweiter, unabhängiger Latenzfaktor:

> "Bluetooth SCO channel negotiation adds 1-3 seconds of delay regardless of whether the mic was idle. This happens on every device switch."

### Pattern B — Ring-Buffer mit Lookback (Apples "engineering-korrekte" Lösung)
Derselbe Autor nennt das Pattern explizit:

> "The correct engineering solution is to keep the audio input stream open between recordings and use a ring buffer with lookback. When the user presses push-to-talk, start reading from the buffer, including audio captured just before the keypress. But apps don't want users seeing 'SuperWhisper is using your microphone' 24/7"

### Pattern C — Implizite Bestätigung durch SuperWhisper
Changelog v1.45.10 (17. Apr 2025): *"Fix handling for push to talk shortcut if microphone is slow to start"* ([superwhisper.com/changelog](https://superwhisper.com/changelog)) — bestätigt, dass auch kommerzielle Apps das Problem nicht elegant lösen, sondern nur "handeln".

### Pattern D — AVAudioEngine.prepare()
Apple's Standard-Empfehlung: `audioEngine.prepare()` vor `.start()` allokiert Ressourcen im Voraus. Erleichtert den späteren Start, beseitigt aber nicht den Hardware-Wakeup ([asciiwwdc.com/2014/sessions/502](https://asciiwwdc.com/2014/sessions/502)).

### Pattern E — Wispr Flow: Latenzbudget 700 ms E2E inkl. LLM
Wispr Flow schweigt zum Audio-Cold-Start, aber ihre Eigenwerbung nennt **p99 700 ms end-to-end** inklusive ASR+LLM+Netzwerk ([wisprflow.ai/post/technical-challenges](https://wisprflow.ai/post/technical-challenges)). Bei diesem Budget ist 400–1500 ms Cold-Start komplett inakzeptabel — sie müssen ebenfalls warmhalten (unbelegt, aber logisch zwingend).

## 2. Interessante Einzelbefunde

- **Orange-Dot-Dilemma:** Warmhalten triggert den macOS-Mic-Indicator permanent. Das ist der eigentliche Grund, warum Apps es nicht tun — nicht technische Schwierigkeit.
- **Teams/Zoom HAL-Plugins sabotieren jede App:** `MSTeamsAudioDevice.driver` und `ZoomAudioDevice.driver` in `/Library/Audio/Plug-Ins/HAL/` erzeugen coreaudiod-CPU-Last (36.8 % idle vs. 0 % ohne) und addieren Startup-Latenz für **alle** Apps.
- **Siri's CSBuiltInVoiceTrigger** kann Push-to-Talk-Recordings nach 5–7 s killen — eigenes Bug-Cluster, nicht Cold-Start.
- **Bluetooth-Teardown-Deadlock:** `AVCaptureSession.stopRunning()` kann hängen, weil CoreAudio's `HALB_Guard` auf eine condition variable des toten BT-Devices wartet. Workaround: stopRunning auf Background-Thread dispatchen.
- **30 s Warm-Window:** Empirisch ~30 s nach letztem Mic-Use bleibt die HW warm.
- **`AVCaptureSession` ≠ `AVAudioEngine` Gap-Problem:** Beide APIs leiden gleichermaßen unter Capture-Gaps bei Device-Switches — das Problem sitzt in coreaudiod selbst ([nonstrict.eu/blog/2024/handling-audio-capture-gaps-on-macos](https://nonstrict.eu/blog/2024/handling-audio-capture-gaps-on-macos/)).
- **Keine Fast-Wake-API:** "As of macOS Tahoe 26.2, no such API exists" — Burchfield hat Feedback bei Apple eingereicht (Feb 2026).

## 3. Lücken der Recherche

- **Zoom/Teams/Meet/Discord interne Implementierung:** Nichts belegbares gefunden. Diese Apps halten den Mic während aktiver Calls ohnehin offen — Cold-Start ist für sie irrelevant. Für Mute/Unmute ist "Mute" softwareseitig (kein Stream-Stop), daher kein Cold-Start. Reverse-Engineering-Berichte existieren nicht öffentlich.
- **Descript/Loom:** Keine technischen Blog-Posts zu Audio-Startup gefunden.
- **macOS Dictation intern:** Apple-Dokus sind oberflächlich. Ab M1 on-device, Aktivierung via Hotkey — aber *wie* Apple den Startup verbirgt (vermutlich systemweites CSBuiltInVoiceTrigger als Daemon, der immer läuft) ist nicht belegt, nur Spekulation.
- **Siri "Hey Siri" Wake-Word:** Dedizierter Low-Power-DSP auf Apple Silicon, aber keine öffentliche API — dritt­apps können das nicht nutzen.
- **WWDC-Talk explizit zu Cold-Start:** Keiner gefunden. WWDC15/507 und WWDC19/510 behandeln AVAudioEngine generisch, nicht Wake-Latenz.

**Kritische Einordnung:** Die Community-Konsens-Lösung (Warmhalten + Ring-Buffer mit Lookback) ist durch einen einzigen Autor (Burchfield) sehr gut dokumentiert, aber **keine Apple-offizielle Guidance existiert**. SuperWhisper's Changelog-Einzeiler ist das einzige indirekte Eingeständnis eines kommerziellen Anbieters.

## Quellen

- [macos-mic-keepwarm (Burchfield, GitHub)](https://github.com/drewburchfield/macos-mic-keepwarm)
- [Wispr Flow: Technical challenges](https://wisprflow.ai/post/technical-challenges)
- [SuperWhisper Changelog](https://superwhisper.com/changelog)
- [Handling audio capture gaps on macOS (Nonstrict)](https://nonstrict.eu/blog/2024/handling-audio-capture-gaps-on-macos/)
- [WhisperKit Issue #44: AVCaptureSession vs AVAudioEngine](https://github.com/argmaxinc/WhisperKit/issues/44)
- [WWDC14/502: AVAudioEngine in Practice](https://asciiwwdc.com/2014/sessions/502)
- [WWDC15/507: What's New in Core Audio](https://asciiwwdc.com/2015/sessions/507)
- [Apple Push to Talk Framework Docs](https://developer.apple.com/documentation/PushToTalk)
- [mikeash: Why CoreAudio is Hard](https://www.mikeash.com/pyblog/why-coreaudio-is-hard.html)
- [HN: Show HN: superwhisper](https://news.ycombinator.com/item?id=37204722)
