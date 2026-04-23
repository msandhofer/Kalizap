# Agent-Report 6 — Open-Source Voice-to-Text Apps: Source-Code-Analyse

**Datum der Recherche:** 2026-04-22
**Rechercheauftrag:** Wie lösen Open-Source-Menubar-Voice-to-Text-Apps auf macOS den Übergang "Hotkey gedrückt" → "Aufnahme läuft wirklich"? Haben sie das Cold-Start-Problem, oder lösen sie es irgendwie? Konkrete Code-Level-Analyse.

---

## Ergebnisse pro App

### 1. AudioWhisper (mazdak) — [Repo](https://github.com/mazdak/AudioWhisper)
- **Audio-API**: `AVAudioRecorder` (File-based, höchste Ebene) — NICHT AVAudioEngine
- **Start-Pattern**: **On-demand, kein Pre-Warm der Hardware**. `AudioRecorder` wird bei App-Launch instantiiert ([AppDelegate+Lifecycle.swift#L28](https://github.com/mazdak/AudioWhisper/blob/master/Sources/App/AppDelegate%2BLifecycle.swift#L28): `audioRecorder = AudioRecorder()`), aber das ruft nur `setupRecorder()` (leer auf macOS) und `checkMicrophonePermission()` — **die Hardware ist noch nicht angetippt**.
- **Relevanter Code**: [AudioRecorder.swift#L84-L142](https://github.com/mazdak/AudioWhisper/blob/master/Sources/Services/Audio/AudioRecorder.swift#L84-L142) — `startRecording()` erstellt `AVAudioRecorder` erst beim Hotkey-Press (`audioRecorder = try recorderFactory(audioFilename, settings)` → `.record()`). AppDelegate+Hotkeys.swift#L121 ruft `recorder.startRecording()` synchron aus dem Hotkey-Handler.
- **Bemerkenswert**: Schreibt direkt in m4a, nicht in ein Float-Buffer. Zahlt Cold-Start voll bei jedem ersten Press.

### 2. pindrop (watzon) — [Repo](https://github.com/watzon/pindrop)
- **Audio-API**: `AVAudioEngine` mit `installTap` + `AVAudioConverter` (plus optional CoreAudio process-tap für System-Audio ab macOS 14.2)
- **Start-Pattern**: **Strikt on-demand, JEDER Recording-Start baut einen neuen `AVAudioEngine` von Null auf**.
- **Relevanter Code**: [AudioRecorder.swift#L302-L348](https://github.com/watzon/pindrop/blob/main/Pindrop/Services/AudioRecorder.swift#L302-L348):
  ```swift
  func startCapture(...) throws {
      _ = audioBuffers.removeAll()
      removeConfigurationChangeObserver()
      let engine = AVAudioEngine()          // fresh jedes Mal
      self.audioEngine = engine
      ...
      inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { ... }
      engine.prepare()
      try engine.start()
  ```
  Im `AppCoordinator.swift#L2280` wird `audioRecorder.startRecording()` nach Hotkey-Toggle gerufen. Kein Prewarm-Pfad irgendwo.
- **Bemerkenswert**: Nutzt `.AVAudioEngineConfigurationChange`-Observer für Device-Wechsel; auf `stop` wird der Engine verworfen (`self.audioEngine = nil`). Null Cold-Start-Mitigation.

### 3. Recap (RecapAI) — [Repo](https://github.com/RecapAI/Recap)
- **Audio-API**: `AVAudioEngine` mit Mixer-Node und Tap
- **Start-Pattern**: **Explizites Background-Prewarm bei `init()`**. Einzige der analysierten Apps mit dediziertem Cold-Start-Fix im Code.
- **Relevanter Code**: [MicrophoneCapture.swift#L29-L86](https://github.com/RecapAI/Recap/blob/main/Recap/Audio/Capture/MicrophoneCapture.swift#L29-L86):
  ```swift
  var preparationTask: Task<Void, Never>?
  var isPreWarmed = false

  init() {
      startBackgroundPreparation()   // sofort async
  }

  func start(outputURL: URL, ...) throws {
      ...
      waitForPreWarmIfNeeded()       // max 100ms busy-wait
      try startAudioEngine()
  }

  private func waitForPreWarmIfNeeded() {
      let startTime = CFAbsoluteTimeGetCurrent()
      while !isPreWarmed && (CFAbsoluteTimeGetCurrent() - startTime) < 0.1 {
          usleep(1000)
      }
  }
  ```
  Und [MicrophoneCapture+AudioEngine.swift#L6-L49](https://github.com/RecapAI/Recap/blob/main/Recap/Audio/Capture/MicrophoneCapture%2BAudioEngine.swift#L6-L49) macht in `performBackgroundPreparation()` → `prepareAudioEngine()`: `AVAudioEngine()` anlegen, `inputNode.inputFormat(forBus: 0)` abfragen (tippt Hardware an), Mixer-Node attachen, `engine.connect(...)` — aber `engine.start()` passiert erst in `startAudioEngine()`. Das spart die Format-Enumeration und Node-Graph-Konstruktion, **nicht aber den eigentlichen `coreaudiod`-Hardware-Wakeup**.
- **Bemerkenswert**: Einziger Commit bisher („Initial Commit" 2025-08-02) — Prewarm war von Anfang an Teil des Designs, keine Bug-Historie.

### 4. WhisperKit AudioProcessor (argmaxinc) — [Repo](https://github.com/argmaxinc/WhisperKit)
- **Audio-API**: `AVAudioEngine` + Tap + `AVAudioConverter` (→ 16kHz Float32)
- **Start-Pattern**: **Lazy, pro `startRecordingLive()`**. Kein Prewarm.
- **Relevanter Code**: [AudioProcessor.swift#L974-L1022](https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Audio/AudioProcessor.swift#L974-L1022) — `setupEngine()` macht `AVAudioEngine()` → `installTap` → `prepare()` → `start()` alles in einem Rutsch, aufgerufen aus `startRecordingLive` (Zeile 1036). Library-Ebene — User muss Warmup selbst bauen.

### 5. MacWhisper (closed source) — [goodsnooze.com](https://goodsnooze.com)
- **Audio-API**: unbekannt.
- **Beobachtung aus Reviews**: MacWhisper ist primär File-Transkription, kein Real-Time-Dictation-Tool. Latenz-Problem bezieht sich dort auf Transcribe-Dauer, nicht Capture-Start. Siehe [jamesm.blog Vergleich](https://jamesm.blog/ai/mac-dictation-tools-comparison/).

### 6. Superwhisper/WhisprFlow (closed source)
- **Beobachtung**: [macos-mic-keepwarm README](https://github.com/drewburchfield/macos-mic-keepwarm/blob/master/README.md) dokumentiert **genau unser Problem** beim M4 MacBook Air auf macOS Tahoe 26.2: „The mic hardware goes to sleep after ~30s of inactivity; next capture start takes 2-5 seconds." Autor zitiert SuperWhisper-Changelog: *„handling push to talk shortcut if microphone is slow to start"*. SuperWhisper hat also den Bug, wurschtelt aber nur dran rum. [Superwhisper Homepage](https://superwhisper.com/)

### 7. macos-mic-keepwarm (drewburchfield) — der Reference-Hack — [Repo](https://github.com/drewburchfield/macos-mic-keepwarm)
- **Audio-API**: `AVCaptureSession` + `AVCaptureAudioDataOutput` (nicht AVAudioEngine!)
- **Start-Pattern**: **Permanent offen als separater LaunchAgent**, Samples werden verworfen.
- **Relevanter Code**: [main.swift#L258-L278](https://github.com/drewburchfield/macos-mic-keepwarm/blob/master/Sources/MicWarm/main.swift#L258-L278):
  ```swift
  let s = AVCaptureSession()
  let input = try AVCaptureDeviceInput(device: device)
  s.addInput(input)
  let output = AVCaptureAudioDataOutput()
  output.setSampleBufferDelegate(self, queue: .main)
  s.addOutput(output)
  s.startRunning()
  ```
  Plus CoreAudio property listener auf `kAudioHardwarePropertyDefaultInputDevice` für Device-Switch-Recovery und Heartbeat-Timer gegen Bluetooth-Deadlocks (`HALB_Guard`-Problem).
- **Bemerkenswert**: Orange Mic-Indicator ist dauerhaft an — der Grund, warum normale Apps das nicht tun. Autor's O-Ton ([README#L110](https://github.com/drewburchfield/macos-mic-keepwarm/blob/master/README.md?plain=1#L110)): *„The correct engineering solution is to keep the audio input stream open between recordings and use a ring buffer with lookback. When the user presses push-to-talk, start reading from the buffer, including audio captured just before the keypress."*

### Weitere gefundene Apps (kürzer)
- **speak2** (zachswift615) — Sliding-Window-Engine, Doku warnt: „first transcription may be slightly slower as the model warms up" (bezieht sich auf Modell, nicht Mic). [Repo](https://github.com/zachswift615/speak2)
- **openwhisper-app** (Rajvardhman05) — AVAudioEngine + GlobalHotkey, on-demand. [Repo](https://github.com/Rajvardhman05/openwhisper-app)
- **push-to-talk-dictate** (Rasala) — MLX-Whisper push-to-talk. [Repo](https://github.com/Rasala/push-to-talk-dictate)
- **voxt** (hehehai) — press-to-talk, release-to-paste. [Repo](https://github.com/hehehai/voxt)

---

### Gemeinsamkeiten

Alle analysierten Apps außer **Recap** starten `AVAudioEngine`/`AVAudioRecorder` **erst beim Hotkey-Press**. Keine hält die Mic-Hardware durchgehend wach. Alle zahlen entsprechend den vollen coreaudiod-/HAL-Cold-Start bei erstem Press nach Idle.

### Unterschiede

- **Recap** ist die einzige mit dediziertem Prewarm (`isPreWarmed`, `preparationTask`). Aber: es baut nur den Node-Graph vor — `engine.start()` passiert trotzdem erst im Hotkey-Pfad. Spart vielleicht 50-150ms Swift-Init, aber den echten coreaudiod-Hardware-Wakeup nicht.
- **AudioWhisper** nutzt als einzige `AVAudioRecorder` (File), alle anderen `AVAudioEngine` (Buffer).
- **pindrop** ist am neuesten und hat die sauberste Architektur (Backend-Protocol, Mock-testable), aber ignoriert Cold-Start komplett.
- **macos-mic-keepwarm** ist nicht selbst eine Voice-App, sondern der externe Workaround — der einzige Code im OSS-Umfeld, der das Problem *tatsächlich* löst, indem `AVCaptureSession` permanent offen bleibt. Das bestätigt: die richtige Lösung ist Stream permanent halten + Ring-Buffer mit Lookback.

### Lücken

- **MacWhisper, Superwhisper, WhisprFlow**: closed source; nur Changelog-Hinweise und Drittberichte verfügbar.
- **Fluid Voice, Whispering**: Keine brauchbaren Open-Source-macOS-Swift-Ergebnisse gefunden, die zum Thema Menubar-PTT passten (Whispering ist Web-App).
- **WhisperKit-Issues**: GitHub-Search-API verweigerte Abfragen zu prewarm/cold-start.

### Kern-Fazit

Die „richtige" Lösung gegen das 400-1500ms-Problem ist nicht Prewarm-at-init (wie Recap), sondern **Audio-Stream permanent offen halten** + Ring-Buffer mit Lookback — wie es macos-mic-keepwarm extern macht. Der orange Mic-Indicator ist der Preis. Recap's Ansatz ist ein guter Kompromiss (kein permanent orange Dot), spart aber realistisch nur einen Teil der Latenz — den teuren `coreaudiod`-Wakeup hat man weiterhin.

## Quellen

- [pindrop AudioRecorder.swift](https://github.com/watzon/pindrop/blob/main/Pindrop/Services/AudioRecorder.swift)
- [pindrop AppCoordinator.swift](https://github.com/watzon/pindrop/blob/main/Pindrop/AppCoordinator.swift)
- [AudioWhisper AudioRecorder.swift](https://github.com/mazdak/AudioWhisper/blob/master/Sources/Services/Audio/AudioRecorder.swift)
- [AudioWhisper AppDelegate+Lifecycle.swift](https://github.com/mazdak/AudioWhisper/blob/master/Sources/App/AppDelegate%2BLifecycle.swift)
- [Recap MicrophoneCapture.swift](https://github.com/RecapAI/Recap/blob/main/Recap/Audio/Capture/MicrophoneCapture.swift)
- [Recap MicrophoneCapture+AudioEngine.swift](https://github.com/RecapAI/Recap/blob/main/Recap/Audio/Capture/MicrophoneCapture%2BAudioEngine.swift)
- [WhisperKit AudioProcessor.swift](https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Audio/AudioProcessor.swift)
- [macos-mic-keepwarm main.swift](https://github.com/drewburchfield/macos-mic-keepwarm/blob/master/Sources/MicWarm/main.swift)
- [macos-mic-keepwarm README](https://github.com/drewburchfield/macos-mic-keepwarm)
- [Mac dictation comparison](https://jamesm.blog/ai/mac-dictation-tools-comparison/)
- [Superwhisper](https://superwhisper.com/)
