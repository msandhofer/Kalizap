# Waveform-Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animiertes Frequenz-Spektrum als schwebendes Overlay oben Mitte während der Aufnahme, plus dieselbe Darstellung im Menüleisten-Popover.

**Architecture:** Neue pure Funktion `AudioSpectrumCalculator` (vDSP-FFT → 20 log-Bänder). `AudioSpectrumProvider`-Protokoll liefert `AsyncStream<[Float]>`. `AudioRecorderImpl` implementiert beides parallel zum bestehenden `AudioLevelMetering`. `DictationPipeline` konsumiert den Stream und hält `spectrumBands: [Float]`. `SpectrumView` rendert Balken. `SpectrumOverlayWindow` zeigt schwebendes NSPanel analog zum bestehenden `ToastWindow`. Overlay-Lifecycle wird über neues `SpectrumOverlayPresenting`-Protokoll an `DictationPipeline.handleStart/handleStop` gekoppelt — so wird der App-Layer (NSPanel) sauber von der Kernlogik entkoppelt.

**Tech Stack:** Swift 6.2, macOS 26, SwiftUI, AppKit (NSPanel), Accelerate/vDSP, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-04-17-waveform-overlay-design.md`

---

## File Structure

**Create:**
- `Sources/DerFluisterer/Services/AudioSpectrumCalculator.swift` — pure FFT → 20 log-Bänder (stateful wegen vDSP-Setup-Cache)
- `Sources/DerFluistererApp/Views/SpectrumView.swift` — SwiftUI-Balken-View
- `Sources/DerFluistererApp/SpectrumOverlayWindow.swift` — floating NSPanel
- `Tests/DerFluistererTests/AudioSpectrumCalculatorTests.swift` — Unit-Tests für FFT

**Modify:**
- `Sources/DerFluisterer/Modules/AudioRecorder.swift` — neues Protokoll `AudioSpectrumProvider`, `AudioRecording` inkludiert es
- `Sources/DerFluisterer/Services/AudioRecorderImpl.swift` — `spectrumStream`-Continuation, `onSpectrum`-Callback im Adapter
- `Sources/DerFluisterer/Modules/DictationPipeline.swift` — `spectrumBands` + `spectrumTask`, `SpectrumOverlayPresenting`-Dependency, Show/Hide in handleStart/handleStop/shutdown
- `Sources/DerFluistererApp/PipelineFactory.swift` — `SpectrumOverlayWindow` als Overlay-Presenter injizieren
- `Sources/DerFluistererApp/Views/MenuBarView.swift` — `WaveformView` → `SpectrumView`
- `Sources/DerFluisterer/Modules/RecordingViewModel.swift` — `waveformLevels` + `updateLevel` + `maxBars` entfernen (RecordingViewModel selbst bleibt wegen RecordingCoordinator)
- `Tests/DerFluistererTests/RecordingViewModelTests.swift` — Tests für `updateLevel`/`waveformLevels` entfernen

**Delete:**
- `Sources/DerFluistererApp/Views/WaveformView.swift`

---

## Task 1: AudioSpectrumCalculator (FFT + log-Bänder, pure)

**Files:**
- Create: `Sources/DerFluisterer/Services/AudioSpectrumCalculator.swift`
- Test: `Tests/DerFluistererTests/AudioSpectrumCalculatorTests.swift`

Design-Constraints:
- FFT-Länge fix: 1024 Samples. Input < 1024 → zero-pad. Input > 1024 → letzte 1024 Samples (neueste)
- Sample-Rate: übergeben (App nutzt 16 kHz)
- Frequenzbereich: 80 Hz – 8 kHz in 20 logarithmischen Bändern
- Hann-Window vor FFT
- Magnituden werden dB-umgerechnet und auf `[0, 1]` gemappt: `-60 dB → 0`, `0 dB → 1`, geclampt
- Setup (FFT-Setup + Hann-Window) wird einmalig im Init gecached — Klasse statt enum
- Thread-Affinität: Aufruf aus Audio-Callback (einzelner Thread) — kein Locking nötig

### Step 1.1: Failing Tests schreiben

- [ ] Datei `Tests/DerFluistererTests/AudioSpectrumCalculatorTests.swift`:

```swift
import Testing
import Foundation
@testable import DerFluisterer

@Suite("AudioSpectrumCalculator")
struct AudioSpectrumCalculatorTests {

    @Test("returns 20 bands of zeros for empty samples")
    func emptySamples() {
        let calc = AudioSpectrumCalculator()
        let bands = calc.calculate(from: [], sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test("returns 20 bands of zeros for silence")
    func silence() {
        let calc = AudioSpectrumCalculator()
        let silence = [Float](repeating: 0, count: 2048)
        let bands = calc.calculate(from: silence, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test("all band values are in [0, 1]")
    func clamped() {
        let calc = AudioSpectrumCalculator()
        // Loud 1 kHz sine — amplitude 1.0 is fullscale
        let samples = (0..<2048).map { i in
            sinf(2 * .pi * 1_000 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("440 Hz sine peaks in a low band")
    func sine440Peak() {
        let calc = AudioSpectrumCalculator()
        // 440 Hz sine, 1024 samples at 16 kHz
        let samples = (0..<1024).map { i in
            0.5 * sinf(2 * .pi * 440 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        // 440 Hz lies between 80 Hz and 8 kHz — in a low band (index < 10)
        guard let maxIndex = bands.indices.max(by: { bands[$0] < bands[$1] }) else {
            Issue.record("no max band found")
            return
        }
        #expect(maxIndex < 10)
    }

    @Test("4 kHz sine peaks in a high band")
    func sine4kHzPeak() {
        let calc = AudioSpectrumCalculator()
        let samples = (0..<1024).map { i in
            0.5 * sinf(2 * .pi * 4_000 * Float(i) / 16_000)
        }
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        guard let maxIndex = bands.indices.max(by: { bands[$0] < bands[$1] }) else {
            Issue.record("no max band found")
            return
        }
        #expect(maxIndex >= 15)
    }

    @Test("short input is zero-padded and still returns 20 bands")
    func zeroPadShortInput() {
        let calc = AudioSpectrumCalculator()
        let samples: [Float] = [0.1, -0.1, 0.1, -0.1]
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.count == 20)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("long input uses last 1024 samples")
    func usesLastSamples() {
        let calc = AudioSpectrumCalculator()
        // 4000 samples: first half silence, second half a 2 kHz tone
        var samples = [Float](repeating: 0, count: 2000)
        let tone = (0..<2000).map { i in
            0.5 * sinf(2 * .pi * 2_000 * Float(i) / 16_000)
        }
        samples.append(contentsOf: tone)
        let bands = calc.calculate(from: samples, sampleRate: 16_000)
        #expect(bands.contains { $0 > 0 })
    }
}
```

### Step 1.2: Tests laufen lassen, FAIL verifizieren

- [ ] Run: `swift test --filter AudioSpectrumCalculatorTests`
  Expected: Compile-Fehler ("cannot find 'AudioSpectrumCalculator'")

### Step 1.3: AudioSpectrumCalculator implementieren

- [ ] Datei `Sources/DerFluisterer/Services/AudioSpectrumCalculator.swift`:

```swift
import Foundation
import Accelerate

/// Berechnet ein Frequenz-Spektrum aus Audio-Samples: FFT über 1024 Samples,
/// Hann-Window, Magnitudengruppierung auf 20 logarithmische Bänder
/// im Bereich 80 Hz – 8 kHz, dB-Skala auf [0, 1] geclampt.
///
/// FFT-Setup und Hann-Window werden einmalig im Init erstellt und gecached.
/// Aufrufe sollten aus einem einzigen Thread erfolgen (z. B. Audio-Callback).
public final class AudioSpectrumCalculator: @unchecked Sendable {
    public static let bandCount = 20
    public static let fftSize = 1024

    private static let minFrequency: Float = 80
    private static let maxFrequency: Float = 8_000
    private static let minDb: Float = -60
    private static let maxDb: Float = 0

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]

    public init() {
        self.log2n = vDSP_Length(log2(Float(Self.fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed")
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    public func calculate(from samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty else {
            return [Float](repeating: 0, count: Self.bandCount)
        }

        let windowed = applyWindow(to: samples)
        let magnitudes = computeMagnitudes(windowed)
        return mapToLogBands(magnitudes: magnitudes, sampleRate: sampleRate)
    }

    // MARK: - Private

    private func applyWindow(to samples: [Float]) -> [Float] {
        var buffer = [Float](repeating: 0, count: Self.fftSize)
        if samples.count >= Self.fftSize {
            let start = samples.count - Self.fftSize
            for i in 0..<Self.fftSize {
                buffer[i] = samples[start + i]
            }
        } else {
            for i in 0..<samples.count {
                buffer[i] = samples[i]
            }
        }
        vDSP_vmul(buffer, 1, hannWindow, 1, &buffer, 1, vDSP_Length(Self.fftSize))
        return buffer
    }

    private func computeMagnitudes(_ windowed: [Float]) -> [Float] {
        let halfSize = Self.fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        // sqrt to go from power to amplitude
        var amplitudes = [Float](repeating: 0, count: halfSize)
        var len = Int32(halfSize)
        vvsqrtf(&amplitudes, magnitudes, &len)
        return amplitudes
    }

    private func mapToLogBands(magnitudes: [Float], sampleRate: Int) -> [Float] {
        let halfSize = magnitudes.count
        let binWidth = Float(sampleRate) / Float(Self.fftSize)

        let logMin = log2(Self.minFrequency)
        let logMax = log2(Self.maxFrequency)
        let bandWidthLog = (logMax - logMin) / Float(Self.bandCount)

        var bands = [Float](repeating: 0, count: Self.bandCount)

        for band in 0..<Self.bandCount {
            let fLow = pow(2, logMin + Float(band) * bandWidthLog)
            let fHigh = pow(2, logMin + Float(band + 1) * bandWidthLog)
            let kLow = max(0, Int(fLow / binWidth))
            let kHigh = min(halfSize - 1, Int(fHigh / binWidth))

            guard kLow <= kHigh else {
                bands[band] = 0
                continue
            }

            // Max amplitude in the band (more responsive than average)
            var peak: Float = 0
            for k in kLow...kHigh where magnitudes[k] > peak {
                peak = magnitudes[k]
            }

            // Normalize amplitude to dB, then to [0, 1]
            let reference = Float(Self.fftSize) / 2
            let normalized = peak / reference
            let db: Float
            if normalized > 0 {
                db = 20 * log10(normalized)
            } else {
                db = Self.minDb
            }
            let clamped = max(Self.minDb, min(Self.maxDb, db))
            bands[band] = (clamped - Self.minDb) / (Self.maxDb - Self.minDb)
        }

        return bands
    }
}
```

### Step 1.4: Tests laufen lassen, PASS verifizieren

- [ ] Run: `swift test --filter AudioSpectrumCalculatorTests`
  Expected: alle 7 Tests PASS

### Step 1.5: Commit

- [ ] Run:

```bash
git add Sources/DerFluisterer/Services/AudioSpectrumCalculator.swift Tests/DerFluistererTests/AudioSpectrumCalculatorTests.swift
git commit -m "feat(#38): AudioSpectrumCalculator fuer FFT-basierte Frequenzbaender"
```

---

## Task 2: AudioSpectrumProvider-Protokoll

**Files:**
- Modify: `Sources/DerFluisterer/Modules/AudioRecorder.swift`

### Step 2.1: Protokoll hinzufügen

- [ ] In `Sources/DerFluisterer/Modules/AudioRecorder.swift` nach dem `AudioLevelMetering`-Protokoll (nach Zeile 65) einfügen:

```swift
public protocol AudioSpectrumProviding: AnyObject, Sendable {
    /// Stream aus 20 normalisierten Frequenzband-Werten im Bereich [0, 1].
    var spectrumStream: AsyncStream<[Float]> { get }
}
```

- [ ] In derselben Datei die Zeile `public protocol AudioRecording: AudioCapturing, AudioLevelMetering, AudioDeviceManaging {}` ersetzen durch:

```swift
public protocol AudioRecording: AudioCapturing, AudioLevelMetering, AudioSpectrumProviding, AudioDeviceManaging {}
```

### Step 2.2: Build-Check

- [ ] Run: `swift build`
  Expected: Build-Fehler in `AudioRecorderImpl.swift` ("does not conform to 'AudioSpectrumProviding'") — das fixen wir in Task 3

### Step 2.3: Noch nicht committen — zusammen mit Task 3

---

## Task 3: AudioRecorderImpl — spectrumStream integrieren

**Files:**
- Modify: `Sources/DerFluisterer/Services/AudioRecorderImpl.swift`

### Step 3.1: Stream + Continuation in der Klasse anlegen

- [ ] In `AudioRecorderImpl`, direkt unter `private var levelContinuation: ...` (nach Zeile 8), ergänzen:

```swift
    private var spectrumContinuation: AsyncStream<[Float]>.Continuation?
```

- [ ] Im `AudioLevelMetering`-Abschnitt (nach Zeile 23), unter `public let levelStream: AsyncStream<AudioLevel>`, ergänzen:

```swift
    // MARK: - AudioSpectrumProviding

    public let spectrumStream: AsyncStream<[Float]>
```

### Step 3.2: Init erweitern

- [ ] In `init(...)` in `AudioRecorderImpl` (nach der `devicesCont`-Initialisierung, vor dem `AudioQueueAdapter`-Aufruf), ergänzen:

```swift
        var spectrumCont: AsyncStream<[Float]>.Continuation?
        self.spectrumStream = AsyncStream { spectrumCont = $0 }
        self.spectrumContinuation = spectrumCont

        let spectrumCalculator = AudioSpectrumCalculator()
```

- [ ] Den bestehenden `AudioQueueAdapter(...)`-Aufruf so anpassen, dass ein `onSpectrum`-Callback übergeben wird:

```swift
        let adapter = AudioQueueAdapter(
            sampleRate: AudioProcessingUtils.transcriptionSampleRate,
            noiseSuppressor: noiseSuppressor,
            spectrumCalculator: spectrumCalculator,
            onLevel: { level in
                levelCont?.yield(level)
            },
            onSpectrum: { bands in
                spectrumCont?.yield(bands)
            }
        )
```

### Step 3.3: AudioQueueAdapter erweitern

- [ ] In `AudioQueueAdapter` (Zeilen 86–100), die Properties erweitern:

```swift
    private let spectrumCalculator: AudioSpectrumCalculator
    private let onLevel: (AudioLevel) -> Void
    private let onSpectrum: ([Float]) -> Void
```

- [ ] Und den Init entsprechend:

```swift
    init(
        sampleRate: Int,
        noiseSuppressor: DeepFilterProcessor? = nil,
        spectrumCalculator: AudioSpectrumCalculator,
        onLevel: @escaping (AudioLevel) -> Void,
        onSpectrum: @escaping ([Float]) -> Void
    ) {
        self.outputSampleRate = sampleRate
        self.noiseSuppressor = noiseSuppressor
        self.spectrumCalculator = spectrumCalculator
        self.onLevel = onLevel
        self.onSpectrum = onSpectrum
    }
```

### Step 3.4: handleBuffer erweitern

- [ ] In `AudioQueueAdapter.handleBuffer(_:)` (Zeile 176), nach `onLevel(chunk.level)` (Zeile 187) ergänzen:

```swift
        let bands = spectrumCalculator.calculate(from: samples, sampleRate: outputSampleRate)
        onSpectrum(bands)
```

### Step 3.5: Build + smoke test

- [ ] Run: `swift build`
  Expected: PASS

- [ ] Run: `swift test`
  Expected: alle bisherigen Tests laufen weiter (keine Regressionen)

### Step 3.6: Commit

- [ ] Run:

```bash
git add Sources/DerFluisterer/Modules/AudioRecorder.swift Sources/DerFluisterer/Services/AudioRecorderImpl.swift
git commit -m "feat(#38): AudioSpectrumProviding + spectrumStream im AudioRecorder"
```

---

## Task 4: DictationPipeline — Spektrum konsumieren + Overlay-Hook

**Files:**
- Modify: `Sources/DerFluisterer/Modules/DictationPipeline.swift`

### Step 4.1: SpectrumOverlayPresenting-Protokoll definieren

- [ ] In `Sources/DerFluisterer/Modules/DictationPipeline.swift`, direkt unter `private let logger = Logger(...)` (nach Zeile 11) einfügen:

```swift
/// Kleines Kontrakt für einen Overlay-Presenter, den die Pipeline beim
/// Aufnahme-Start öffnet und beim Stop schließt. Implementierung lebt in
/// der App-Schicht (NSPanel).
@MainActor
public protocol SpectrumOverlayPresenting: AnyObject {
    func show(pipeline: DictationPipeline)
    func hide()
}
```

### Step 4.2: PipelineDependencies erweitern

- [ ] In `PipelineDependencies` (ab Zeile 60):
  - Nach `public let metering: any AudioLevelMetering` (Zeile 63) ergänzen:

```swift
    public let spectrumProvider: any AudioSpectrumProviding
    public let overlayPresenter: (any SpectrumOverlayPresenting)?
```

  - Den Init entsprechend erweitern (nach `metering:` und vor `transcriber:`):

```swift
        metering: any AudioLevelMetering,
        spectrumProvider: any AudioSpectrumProviding,
        overlayPresenter: (any SpectrumOverlayPresenting)? = nil,
        transcriber: any TranscriptionEngine,
```

  - Und im Init-Body:

```swift
        self.metering = metering
        self.spectrumProvider = spectrumProvider
        self.overlayPresenter = overlayPresenter
        self.transcriber = transcriber
```

### Step 4.3: spectrumBands-Property + Task

- [ ] In `DictationPipeline` (ab Zeile 128), nach `public private(set) var audioLevel: Float = 0` ergänzen:

```swift
    public private(set) var spectrumBands: [Float] = Array(repeating: 0, count: 20)
```

- [ ] Nach `private var levelTask: Task<Void, Never>?` (Zeile 140) ergänzen:

```swift
    private var spectrumTask: Task<Void, Never>?
```

- [ ] Neue private Methode direkt unter `startLevelMetering()` (nach Zeile 423) hinzufügen:

```swift
    private func startSpectrumMetering() {
        let provider = deps.spectrumProvider

        spectrumTask = Task { [weak self] in
            guard let self else { return }
            for await bands in provider.spectrumStream {
                if Task.isCancelled { break }
                await MainActor.run { self.spectrumBands = bands }
            }
        }
    }
```

### Step 4.4: Lifecycle anpassen (start/stop/shutdown)

- [ ] In `stopStreamingAndMetering()` (ab Zeile 258), innerhalb der Methode den spectrumTask abräumen und Overlay verbergen (wichtig für cancelDictation/deactivate-Pfad):

```swift
    private func stopStreamingAndMetering() {
        streamingTask?.cancel()
        streamingTask = nil
        levelTask?.cancel()
        levelTask = nil
        spectrumTask?.cancel()
        spectrumTask = nil
        audioLevel = 0
        spectrumBands = Array(repeating: 0, count: 20)
        deps.overlayPresenter?.hide()
    }
```

- [ ] In `stopLevelMetering()` (ab Zeile 300) dasselbe (da diese Methode bei handleStop() vor der Sound/Recorder-Stop-Sequenz läuft):

```swift
    private func stopLevelMetering() {
        levelTask?.cancel()
        levelTask = nil
        spectrumTask?.cancel()
        spectrumTask = nil
        audioLevel = 0
        spectrumBands = Array(repeating: 0, count: 20)
        deps.overlayPresenter?.hide()
    }
```

- [ ] In `handleStart()` (ab Zeile 266), nach `startLevelMetering()` (Zeile 281) ergänzen:

```swift
            startSpectrumMetering()
            deps.overlayPresenter?.show(pipeline: self)
```

### Step 4.5: Build + Test

- [ ] Run: `swift build`
  Expected: Build-Fehler in `PipelineFactory.swift` und evtl. Tests (wegen neuer `spectrumProvider`-Dependency). Das fixen wir in Task 5.

### Step 4.6: PipelineFactory anpassen

- [ ] In `Sources/DerFluistererApp/PipelineFactory.swift` die `PipelineDependencies(...)`-Erzeugung suchen und den `recorder` zweifach als `spectrumProvider` übergeben (der `AudioRecorderImpl` implementiert beides):
  - `metering: recorder,` Zeile suchen → direkt darunter ergänzen: `spectrumProvider: recorder,`
  - `overlayPresenter: SpectrumOverlayWindow.shared,` — **ACHTUNG:** `SpectrumOverlayWindow.shared` existiert erst nach Task 7. In dieser Task nur `overlayPresenter: nil,` eintragen oder den Parameter weglassen (Default ist nil).

### Step 4.7: Tests anpassen

- [ ] `Tests/DerFluistererTests/TestHelpers.swift` lesen und prüfen, ob es dort einen `PipelineDependencies(...)`-Konstruktor-Helper gibt. Falls ja: `spectrumProvider`-Parameter hinzufügen. Falls nicht direkt dort, dann in allen Stellen die `PipelineDependencies(...)` aufrufen.
  - Mock einen `MockAudioSpectrumProvider`:

```swift
final class MockAudioSpectrumProvider: AudioSpectrumProviding, @unchecked Sendable {
    let spectrumStream: AsyncStream<[Float]>
    private let continuation: AsyncStream<[Float]>.Continuation

    init() {
        var cont: AsyncStream<[Float]>.Continuation!
        self.spectrumStream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func emit(_ bands: [Float]) {
        continuation.yield(bands)
    }

    func finish() {
        continuation.finish()
    }
}
```

  - An allen Stellen, wo `PipelineDependencies(...)` instanziiert wird, `spectrumProvider: MockAudioSpectrumProvider()` ergänzen.

- [ ] Run: `swift build`
  Expected: PASS

- [ ] Run: `swift test`
  Expected: alle Tests PASS

### Step 4.8: Commit

- [ ] Run:

```bash
git add Sources/DerFluisterer/Modules/DictationPipeline.swift Sources/DerFluistererApp/PipelineFactory.swift Tests/DerFluistererTests/
git commit -m "feat(#38): DictationPipeline konsumiert spectrumStream + Overlay-Hook"
```

---

## Task 5: SpectrumView (SwiftUI-Balken)

**Files:**
- Create: `Sources/DerFluistererApp/Views/SpectrumView.swift`

### Step 5.1: View schreiben

- [ ] Datei `Sources/DerFluistererApp/Views/SpectrumView.swift`:

```swift
import SwiftUI

struct SpectrumView: View {
    let bands: [Float]
    let barCount: Int
    let height: CGFloat
    let barWidth: CGFloat
    let spacing: CGFloat
    let color: Color

    init(
        bands: [Float],
        barCount: Int = 20,
        height: CGFloat = 22,
        barWidth: CGFloat = 2.5,
        spacing: CGFloat = 3,
        color: Color = Color(red: 0x0A/255.0, green: 0x84/255.0, blue: 0xFF/255.0)
    ) {
        self.bands = bands
        self.barCount = barCount
        self.height = height
        self.barWidth = barWidth
        self.spacing = spacing
        self.color = color
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: barWidth, height: barHeight(at: index))
                    .animation(.easeOut(duration: 0.08), value: bands)
            }
        }
        .frame(height: height)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let minHeight: CGFloat = 3
        let value: Float
        if index < bands.count {
            value = bands[index]
        } else {
            value = 0
        }
        return minHeight + CGFloat(value) * (height - minHeight)
    }
}

#Preview {
    SpectrumView(bands: (0..<20).map { Float($0) / 20 })
        .padding()
        .background(.ultraThinMaterial)
}
```

### Step 5.2: Build verifizieren

- [ ] Run: `swift build`
  Expected: PASS

### Step 5.3: Commit

- [ ] Run:

```bash
git add Sources/DerFluistererApp/Views/SpectrumView.swift
git commit -m "feat(#38): SpectrumView rendert FFT-Baender als SwiftUI-Balken"
```

---

## Task 6: MenuBarView auf SpectrumView umstellen

**Files:**
- Modify: `Sources/DerFluistererApp/Views/MenuBarView.swift`

### Step 6.1: RecordingStatusView anpassen

- [ ] In `Sources/DerFluistererApp/Views/MenuBarView.swift`, Zeile 171–181 (`RecordingStatusView`), ersetzen:

```swift
private struct RecordingStatusView: View {
    let bands: [Float]

    var body: some View {
        SpectrumView(bands: bands, barCount: 12, height: 20, barWidth: 2, spacing: 2)
            .padding(.horizontal, 8)
        Text("Aufnahme läuft…")
            .font(.caption)
            .foregroundStyle(.red)
    }
}
```

### Step 6.2: Aufruf anpassen

- [ ] In derselben Datei, Zeile 61, ersetzen:

```swift
                RecordingStatusView(bands: pipeline.spectrumBands)
```

### Step 6.3: Build + Test

- [ ] Run: `swift build`
  Expected: PASS (die alte `WaveformView` ist nun verwaist, bleibt vorerst aber noch existieren — wird in Task 9 gelöscht)

- [ ] Run: `swift test`
  Expected: alle Tests PASS

### Step 6.4: Commit

- [ ] Run:

```bash
git add Sources/DerFluistererApp/Views/MenuBarView.swift
git commit -m "feat(#38): MenuBar-Popover nutzt SpectrumView statt WaveformView"
```

---

## Task 7: SpectrumOverlayWindow (floating NSPanel)

**Files:**
- Create: `Sources/DerFluistererApp/SpectrumOverlayWindow.swift`

### Step 7.1: Fenster implementieren

- [ ] Datei `Sources/DerFluistererApp/SpectrumOverlayWindow.swift`:

```swift
import AppKit
import SwiftUI
import DerFluisterer

/// Schwebendes Overlay oben Mitte mit einem animierten Frequenz-Spektrum.
/// Wird durch DictationPipeline über das SpectrumOverlayPresenting-Protokoll
/// gesteuert: show(pipeline:) bei Aufnahme-Start, hide() bei Stop.
@MainActor
final class SpectrumOverlayWindow: SpectrumOverlayPresenting {
    static let shared = SpectrumOverlayWindow()

    private var window: NSPanel?

    private init() {}

    func show(pipeline: DictationPipeline) {
        if window != nil { return }
        guard let screen = NSScreen.main else { return }

        let content = SpectrumOverlayContent(pipeline: pipeline)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame.size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hostingView.fittingSize.width / 2
        let y = screenFrame.maxY - hostingView.fittingSize.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.window = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
        })
    }
}

private struct SpectrumOverlayContent: View {
    @Bindable var pipeline: DictationPipeline

    var body: some View {
        SpectrumView(bands: pipeline.spectrumBands)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))
    }
}
```

### Step 7.2: Build verifizieren

- [ ] Run: `swift build`
  Expected: PASS

### Step 7.3: Commit

- [ ] Run:

```bash
git add Sources/DerFluistererApp/SpectrumOverlayWindow.swift
git commit -m "feat(#38): SpectrumOverlayWindow — floating NSPanel oben Mitte"
```

---

## Task 8: Overlay-Presenter in PipelineFactory verdrahten

**Files:**
- Modify: `Sources/DerFluistererApp/PipelineFactory.swift`

### Step 8.1: overlayPresenter zuweisen

- [ ] In `Sources/DerFluistererApp/PipelineFactory.swift` die `PipelineDependencies(...)`-Erzeugung: wo in Task 4 `overlayPresenter: nil,` stand, durch:

```swift
            overlayPresenter: SpectrumOverlayWindow.shared,
```

ersetzen. (Falls der Parameter weggelassen wurde: hinzufügen.)

### Step 8.2: Build verifizieren

- [ ] Run: `swift build`
  Expected: PASS

- [ ] Run: `swift test`
  Expected: alle Tests PASS

### Step 8.3: Commit

- [ ] Run:

```bash
git add Sources/DerFluistererApp/PipelineFactory.swift
git commit -m "feat(#38): SpectrumOverlayWindow als Presenter in Pipeline einhaengen"
```

---

## Task 9: Altlasten aufräumen (WaveformView, RecordingViewModel-Waveform)

**Files:**
- Delete: `Sources/DerFluistererApp/Views/WaveformView.swift`
- Modify: `Sources/DerFluisterer/Modules/RecordingViewModel.swift`
- Modify: `Tests/DerFluistererTests/RecordingViewModelTests.swift`

### Step 9.1: WaveformView löschen

- [ ] Run:

```bash
rm "Sources/DerFluistererApp/Views/WaveformView.swift"
```

### Step 9.2: RecordingViewModel aufräumen

- [ ] `Sources/DerFluisterer/Modules/RecordingViewModel.swift` vollständig ersetzen durch:

```swift
import Foundation
import Observation

@Observable
@MainActor
public final class RecordingViewModel {
    public private(set) var isRecording = false
    public private(set) var isPulsing = false

    public var menuBarIcon: String {
        isRecording ? "waveform" : "mic.fill"
    }

    public init() {}

    public func startRecording() {
        isRecording = true
        isPulsing = true
    }

    public func stopRecording() {
        isRecording = false
        isPulsing = false
    }
}
```

### Step 9.3: Tests aufräumen

- [ ] `Tests/DerFluistererTests/RecordingViewModelTests.swift` öffnen und alle `@Test`-Methoden entfernen, die `waveformLevels`, `updateLevel`, `maxWaveformBars` oder `maxBars` referenzieren. Die übrigen Tests (startRecording/stopRecording/menuBarIcon) bleiben erhalten.

- [ ] Falls Tests `RecordingViewModel(maxWaveformBars: 3)` aufrufen: durch `RecordingViewModel()` ersetzen.

### Step 9.4: Build + Test

- [ ] Run: `swift build`
  Expected: PASS

- [ ] Run: `swift test`
  Expected: alle verbleibenden Tests PASS

### Step 9.5: Commit

- [ ] Run:

```bash
git add Sources/DerFluisterer/Modules/RecordingViewModel.swift Tests/DerFluistererTests/RecordingViewModelTests.swift
git rm Sources/DerFluistererApp/Views/WaveformView.swift
git commit -m "refactor(#38): WaveformView + tote waveformLevels-Logik entfernen"
```

---

## Task 10: Manueller End-to-End-Test

**Files:**
- keine

### Step 10.1: App starten

- [ ] Run: `swift run DerFluistererApp`
  Oder im Xcode: Build & Run

### Step 10.2: Manueller Test-Durchlauf

- [ ] Hotkey drücken (Aufnahme starten)
  Erwartet: Overlay erscheint oben Mitte mit Fade-in (~0,2 s)

- [ ] Sprechen
  Erwartet: 20 Balken animieren live; Höhenverteilung wandert mit Tonhöhe (tiefere Töne links, höhere rechts); Höhe folgt Lautstärke

- [ ] Klick auf das Overlay
  Erwartet: Klick geht durch zur App darunter (click-through funktioniert)

- [ ] Hotkey drücken (Aufnahme stoppen)
  Erwartet: Overlay verschwindet mit Fade-out (~0,3 s). Processing-Feedback nur im Menüleisten-Icon.

- [ ] Menüleisten-Icon anklicken während Aufnahme
  Erwartet: Im Popover erscheint die kleinere `SpectrumView` (12 Balken) + „Aufnahme läuft…"

- [ ] System-Theme wechseln (hell/dunkel)
  Erwartet: Overlay-Hintergrund passt sich an (`.ultraThinMaterial`)

- [ ] Vollbild-App öffnen, dann Hotkey drücken
  Erwartet: Overlay erscheint auch über der Vollbild-App (`.canJoinAllSpaces`)

- [ ] Zwei Aufnahmen direkt hintereinander
  Erwartet: zweites Overlay blendet sauber auf, keine Duplikate

### Step 10.3: Abschluss-Commit (falls letzte Änderungen)

- [ ] Nur falls der manuelle Test noch Nacharbeiten erzwungen hat:

```bash
git add -A
git commit -m "fix(#38): Nacharbeit aus manuellem Test"
```

---

## Verifikation

- [ ] `swift build` → PASS
- [ ] `swift test` → alle Tests PASS
- [ ] Spec-Anforderungen abgehakt:
  - Overlay erscheint bei Aufnahme-Start, verschwindet bei Stop ✓ (Task 4 + 7)
  - Animiertes Frequenz-Spektrum (FFT, 20 Bänder, 80 Hz – 8 kHz) ✓ (Task 1)
  - Position oben Mitte ✓ (Task 7)
  - Click-through ✓ (Task 7, `ignoresMouseEvents = true`)
  - Konsistenz mit ToastWindow ✓ (Task 7 — NSPanel-Config gespiegelt)
  - Menüleisten-Popover nutzt dieselbe Darstellung ✓ (Task 6)
  - Fade-in/out ✓ (Task 7)
  - Performance ≤ 0,5 % CPU für FFT → manuell prüfen via Activity Monitor während Aufnahme
