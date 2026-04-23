# Agent-Report 3 — Ring-Buffer mit Lookback / Always-On Audio-Capture

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Kann man den Cold-Start umgehen, indem man die Audio-Aufnahme dauerhaft im Hintergrund laufen lässt und bei Hotkey-Press nur aus einem Ring-Buffer das relevante Segment extrahiert?

---

## 1. Apps, die das Pattern nutzen

**Das exakte Ziel existiert bereits als Open-Source-Tool — allerdings als Companion, nicht als integrierter Ansatz:**

- **`drewburchfield/macos-mic-keepwarm`** — hält das Mikro *permanent geöffnet* mit `AVCaptureSession`, verwirft aber alle Samples. Zweck: das 2–5-Sekunden-Cold-Start-Problem auf Apple Silicon beseitigen. Wird explizit als Companion für *SuperWhisper, WhisperFlow, Wispr Flow* beworben. Das bestätigt zwei Dinge: (a) keine dieser kommerziellen Apps macht es selbst, (b) das Problem ist real und weit verbreitet. ([GitHub Readme](https://github.com/drewburchfield/macos-mic-keepwarm))
- **Wispr Flow** selbst: klassisch push-to-talk, kein Pre-Roll. Es gibt einen "Hands-Free Mode" (Hotkey + Space), aber das ist einfach Toggle-Start, kein Ring-Buffer. ([Wispr Flow Docs](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues))
- **Superwhisper / MacParakeet / Speak2 / Dictate (Rasala)** — alle Push-to-Talk, keiner mit dokumentiertem Always-On-Ring-Buffer. ([Rasala/dictate](https://github.com/Rasala/dictate), [moona3k/macparakeet](https://github.com/moona3k/macparakeet), [zachswift615/speak2](https://github.com/zachswift615/speak2))

**Kein belegbarer Fund einer macOS-Voice-to-Text-App, die einen echten Pre-Trigger-Ring-Buffer mit Rückwärts-Extraktion ("letzte N Sekunden vor Hotkey") implementiert.** Das Pattern ist im Video-Bereich (Milestone XProtect, GoPro) Standard, im STT-Bereich auf macOS nicht auffindbar.

## 2. Technische Machbarkeit

Ring-Buffer-Pattern ist in der CoreAudio-Community gut dokumentiert:

- **TPCircularBuffer** (Michael Tyson / A Tasty Pixel) — De-facto-Standard: lock-free via atomic fill count, single-producer/single-consumer, Virtual-Memory-Mapping-Trick für contiguous reads über den Wrap-Around hinweg. ([atastypixel.com](https://atastypixel.com/a-simple-fast-circular-buffer-implementation-for-audio-processing/), [michaeltyson/TPCircularBuffer](https://github.com/michaeltyson/TPCircularBuffer))
- **AVAudioEngine-Tap** liefert PCM-Buffer fortlaufend über `installTap`, die du direkt in den Ringpuffer schiebst. ([Apple Dev Forum Tag: AVAudioEngine](https://developer.apple.com/forums/tags/avaudioengine))
- Swift-Ports: `Galarius/ring-buffer`, `jaredsinclair/circular-buffer`, `jeremytregunna/Ring` (explizit für audio/video frames). ([Galarius/ring-buffer](https://github.com/Galarius/ring-buffer), [jeremytregunna/Ring](https://github.com/jeremytregunna/Ring))

**Technisch unkritisch**: 16 kHz mono PCM, 10 s Lookback = ~320 KB. `macos-mic-keepwarm` berichtet "~0 % CPU, negligible battery" beim reinen Open-Halten.

## 3. Nachteile und Risiken

- **Privacy-Indicator ist unvermeidbar.** Apple erlaubt das Ausblenden des orangenen Punkts nur auf *externen* Displays ab macOS 14.4 — und nur via `csrutil`-Override im Recovery-Modus. Auf dem Haupt-Display bleibt er permanent sichtbar: *"The privacy indicators still appear on the main display of your Mac."* ([Apple Support 118449](https://support.apple.com/en-us/118449))
- **Wahrnehmungsproblem**: `macos-mic-keepwarm` selbst formuliert den Tradeoff offen — *"the indicator shows continuous access even during idle periods"*.
- **User-Akzeptanz**: Aus einer Clickup-Analyse wörtlich: *"apps don't want users seeing 'SuperWhisper is using your microphone' 24/7, even though the alternative is a broken user experience"*. ([ClickUp: Wispr Flow vs Superwhisper](https://clickup.com/blog/wispr-flow-vs-superwhisper/))
- **App-Store-Review**: Kein belegter Rejection-Fall spezifisch wegen Always-On, aber generische Mikro-Usage-Descriptions werden abgelehnt. ([JUCE Forum](https://forum.juce.com/t/standard-microphone-access-message-app-store-review-rejection/65497))
- **Battery**: keine harten Zahlen außer "negligible" aus dem keepwarm-Repo — keine unabhängige Messung gefunden.

## 4. Empfehlungs-Hinweise (quellenbasiert)

- Das Pattern ist **technisch trivial und bewährt** (TPCircularBuffer seit ~2011).
- **Kein etablierter kommerzieller STT-Konkurrent** implementiert es — das ist ein Signal: entweder echter Wettbewerbsvorteil, oder der Privacy-Indicator-Tradeoff wurde bewusst abgelehnt.
- **Hybrid-Variante** entspricht dem, was `macos-mic-keepwarm` bereits extern macht: Stream offen halten, Samples verwerfen bis Hotkey — nur Cold-Start vermeiden, *ohne* Lookback-Historie. Das nimmt den Privacy-Impact (Indicator an), verzichtet aber auf echten "0 ms pre-trigger".
- **Echte Pre-Trigger-Lookback** (z. B. 2 s vor Keydown mitschneiden) ist zusätzlich möglich, muss aber gegen den permanent sichtbaren orangenen Punkt abgewogen werden — für den User sichtbar identisch zu "Always-On-Recording", auch wenn du faktisch verwirfst.

## Quellen

- [drewburchfield/macos-mic-keepwarm](https://github.com/drewburchfield/macos-mic-keepwarm)
- [atastypixel — A simple, fast circular buffer implementation](https://atastypixel.com/a-simple-fast-circular-buffer-implementation-for-audio-processing/)
- [atastypixel — Circular ring buffer + VM mapping trick](https://atastypixel.com/circular-ring-buffer-plus-neat-virtual-memory-mapping-trick/)
- [michaeltyson/TPCircularBuffer](https://github.com/michaeltyson/TPCircularBuffer)
- [Apple Support 118449 — Hide privacy indicators on external displays](https://support.apple.com/en-us/118449)
- [Wispr Flow Docs — Troubleshooting mic issues](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues)
- [ClickUp — Wispr Flow vs Superwhisper](https://clickup.com/blog/wispr-flow-vs-superwhisper/)
- [Rasala/dictate](https://github.com/Rasala/dictate)
- [moona3k/macparakeet](https://github.com/moona3k/macparakeet)
- [zachswift615/speak2](https://github.com/zachswift615/speak2)
- [gptguy/silentkeys](https://github.com/gptguy/silentkeys)
- [Galarius/ring-buffer Swift](https://github.com/Galarius/ring-buffer)
- [jeremytregunna/Ring](https://github.com/jeremytregunna/Ring)
- [Apple Dev Forums — Audio Unit Circular buffering](https://developer.apple.com/forums/thread/73560)
- [JUCE Forum — App Store rejection standard mic message](https://forum.juce.com/t/standard-microphone-access-message-app-store-review-rejection/65497)
- [Milestone — Pre-buffering explained (conceptual reference)](https://doc.milestonesys.com/latest/en-US/standard_features/sf_mc/sf_mcnodes/sf_3devices/mc_prebufferingexplained_devices.htm)
