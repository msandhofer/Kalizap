# Waveform-Overlay während Sprachaufnahme — Design

**Issue:** #38
**Datum:** 2026-04-17
**Status:** Spec (genehmigt, wartet auf writing-plans)

## Motivation

Während der Sprachaufnahme braucht der Nutzer visuelles Feedback, dass die App zuhört und wie laut sein Eingangssignal ist. Aktuell existiert eine `WaveformView` nur im Menüleisten-Popover — die wird im typischen Hotkey-Workflow nie geöffnet und ist folglich nie sichtbar. Zusätzlich ist die bestehende Einbindung defekt: `WaveformView(levels: [audioLevel])` übergibt nur einen einzigen Wert an eine View, die 20 Balken erwartet; der Rolling-Buffer in `RecordingViewModel.waveformLevels` wird nie konsumiert.

## Designprinzip

**Minimal und unaufdringlich.** Das Overlay ist reine Statusanzeige. Der Nutzer soll sich auf seinen Workflow konzentrieren, nicht auf das Overlay. Deshalb: keine Zeit, keine Buttons, keine Labels. Nur ein animiertes Spektrum als visuelles Lebenszeichen.

## Anforderungen

- Overlay erscheint bei Aufnahme-Start, verschwindet bei Aufnahme-Stop (nicht erst nach Processing)
- Animiertes Frequenz-Spektrum (FFT, 20 logarithmisch gruppierte Bänder, 80 Hz – 8 kHz)
- Position: Oben Mitte, direkt unter Menüleiste
- Click-through: das Overlay fängt keine Mausereignisse ab
- Konsistenz mit bestehendem `ToastWindow` (Fade, Material, `.statusBar`-Level, `.canJoinAllSpaces`)
- Dieselbe Spektrum-Darstellung ersetzt die defekte `WaveformView` im Menüleisten-Popover

## Visuelle Spezifikation

| Aspekt | Wert |
|---|---|
| Position | Bildschirmmitte, 16 px unterhalb der Menüleiste |
| Form | Pill (Kapsel), 999 px corner-radius |
| Größe | ca. 220 × 40 px (passt sich an Balkenanzahl an) |
| Hintergrund | `.ultraThinMaterial`, folgt System-Theme (hell/dunkel) |
| Rand | 0,5 pt `.quaternary`, konsistent mit `ToastContent` |
| Schatten | weich (entspricht `hasShadow = true` des NSPanel) |
| Balkenfarbe | macOS-Akzentblau `#0A84FF` |
| Balken | 20 Stück, Breite 2,5 pt, Abstand 3 pt, corner-radius 2 pt |
| Höhe je Balken | `minHeight + magnitude · (maxHeight − minHeight)` mit `minHeight = 3`, `maxHeight = 22` |
| Einblenden | Fade-in 0,2 s |
| Ausblenden | Fade-out 0,3 s |

### Menüleisten-Popover-Variante

Dieselbe `SpectrumView`, aber kompakter: Höhe 20 pt, Breite ca. 90 pt (weniger Balken oder dünner gerendert). Ersetzt die fehlerhafte `WaveformView`-Einbindung in `MenuBarView.swift`.

## Architektur

### Datenfluss

```
AudioRecorderImpl
  ├─ levelStream:    AsyncStream<AudioLevel>    (bestehend, RMS+Peak)
  └─ spectrumStream: AsyncStream<[Float]>       (neu, 20 normalisierte Bänder)
         │
         ▼
DictationPipeline
  ├─ audioLevel:     Float                      (bestehend)
  └─ spectrumBands:  [Float]                    (neu, @Published)
         │
         ▼
   ┌─────┴─────┐
   ▼           ▼
SpectrumView   SpectrumOverlayWindow
(Popover)      (Floating NSPanel)
```

### Neue Komponenten

**`AudioSpectrumCalculator` (Sources/DerFluisterer/Services/)**
- `static func calculate(from samples: [Float], sampleRate: Int) -> [Float]`
- Hann-Window, Real-to-Complex FFT via `vDSP` (Accelerate.framework)
- Magnituden werden auf 20 Frequenzbänder logarithmisch gruppiert (80 Hz – 8 kHz)
- Jedes Band wird auf `[0, 1]` normalisiert (dB-Skala, geclampt)
- FFT-Setup wird einmal im Initialisierer erstellt und gecached (SIMD-optimiert)
- Reine Funktion, synchron, testbar ohne Audio-Hardware

**`SpectrumView` (Sources/DerFluistererApp/Views/)**
- `let bands: [Float]` (20 Werte, erwartet Werte in `[0, 1]`)
- `let barCount: Int` (default 20)
- `let height: CGFloat` (default 22 für Overlay, 20 für Popover)
- Rendert 20 `RoundedRectangle`-Balken mit Höhe proportional zum Band-Wert
- Ersetzt die bestehende defekte `WaveformView`

**`SpectrumOverlayWindow` (Sources/DerFluistererApp/)**
- `@MainActor enum SpectrumOverlayWindow` (analog zu `ToastWindow`)
- `static func show(bandsBinding: ...)` — öffnet NSPanel mit `SpectrumView`
- `static func hide()` — Fade-out
- NSPanel-Config: `.nonactivatingPanel`, `.statusBar`-Level, `.canJoinAllSpaces`, `.stationary`
- `ignoresMouseEvents = true` (click-through)
- Position: `screen.visibleFrame.midX` horizontal, `screen.visibleFrame.maxY - 16 - height` vertikal
- Panel hält einen `@ObservedObject` oder Callback, um Balken live zu aktualisieren

### Integration

**`AudioRecorderImpl.swift`**
- Neuer Stream `spectrumStream` parallel zum bestehenden `levelStream`
- Im Audio-Tap-Callback (nach `AudioLevelCalculator`) wird zusätzlich `AudioSpectrumCalculator.calculate(...)` aufgerufen
- Wiederverwendung derselben Samples → kein zusätzlicher Speicher

**`DictationPipeline.swift`**
- Neue `@MainActor`-Property `spectrumBands: [Float] = Array(repeating: 0, count: 20)`
- Neuer Task konsumiert `spectrumStream` parallel zum bestehenden `levelStream`-Task
- Reset auf Nullen bei Recording-Stop (wie `audioLevel = 0` an Zeile 263, 303)

**Overlay-Lifecycle**
- `SpectrumOverlayWindow.show(...)` wird aufgerufen, wo heute `audioLevel`-Tracking startet (Recording-Start)
- `SpectrumOverlayWindow.hide()` bei Recording-Stop
- Kopplung idealerweise in `DictationPipeline` oder im App-Layer, der auf `PipelineState` reagiert

**`MenuBarView.swift`**
- `RecordingStatusView` nutzt `SpectrumView(bands: pipeline.spectrumBands)` statt `WaveformView(levels: [audioLevel])`

### Komponenten werden entfernt

- `WaveformView.swift` → ersetzt durch `SpectrumView.swift`
- `RecordingViewModel.waveformLevels` + `updateLevel(_:)` (werden nicht mehr gebraucht, da `spectrumBands` direkt aus Pipeline kommt) — falls `RecordingViewModel` noch anderweitig genutzt wird, bleibt die Klasse, nur die Waveform-Props fliegen raus
- Zugehörige Tests in `RecordingViewModelTests.swift` (updateLevel-Tests) werden entfernt oder angepasst

## Performance

- vDSP-FFT über 512 Samples bei 16 kHz: ca. 20–50 µs pro Frame
- Refresh-Rate: 20 Hz (entspricht bestehender Level-Update-Rate)
- CPU-Last: ca. 0,1 % — vernachlässigbar gegenüber Whisper (5–15 %) und DeepFilterNet3
- Läuft parallel zur Pipeline, nicht im kritischen Pfad — keine Latenz-Auswirkung

## Testing

**Unit-Tests** (`Tests/DerFluistererTests/AudioSpectrumCalculatorTests.swift`, neu)
- `calculate` gibt bei leeren Samples 20 Nullen zurück
- Sinus bei 440 Hz produziert Peak im erwarteten Frequenzband
- Weißes Rauschen produziert ungefähr gleichverteilte Bänder
- Werte liegen alle in `[0, 1]`

**Snapshot-/Rendering-Tests** — nicht für dieses Issue, da `SpectrumView` reine Anzeige-Logik ist

**Manueller Test**
- Aufnahme starten, Overlay erscheint oben Mitte mit Fade-in
- Sprechen → Balken animieren live, Höhe folgt Lautstärke, Verteilung folgt Frequenzinhalt
- Aufnahme stoppen → Overlay verschwindet mit Fade-out
- Hell/Dunkel-Modus wechseln → Overlay passt sich an
- In Vollbild-App wechseln → Overlay bleibt sichtbar (`.canJoinAllSpaces`)
- Auf Overlay klicken → Klick geht durch (click-through)

## Out of Scope

- Cancel-Button im Overlay (bewusst ausgeklammert, "minimal")
- Zeitanzeige (bewusst ausgeklammert, "lenkt ab")
- Overlay bei Cursor-Position (D-Variante aus Brainstorming, zu komplex)
- Klick auf Overlay, um Aufnahme zu stoppen (zukünftiges Feature ggf. in separatem Issue)

## Offene technische Annahmen

- `vDSP`-FFT-Setup ist thread-safe bzw. wird im Audio-Thread verwendet (AudioRecorder läuft dort). Verifizieren vor Implementierung.
- `NSPanel` mit `.ignoresMouseEvents = true` + `.canJoinAllSpaces` funktioniert zuverlässig mit Vollbild-Apps. Entspricht dem bestehenden `ToastWindow`-Pattern, sollte übertragbar sein.
