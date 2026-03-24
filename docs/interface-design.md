# DerFlüsterer — Interface Design Decisions

Stand: 2026-03-24

## Shared Types

```swift
enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case de, en
}

enum ContextMode: String, Codable, CaseIterable, Sendable {
    case formal, informal, neutral, auto
}

struct CorrectionIntensity: Codable, Equatable, Sendable {
    var allowRephrasing: Bool = false
    var allowShortening: Bool = false
    var allowRestructuring: Bool = false
}

enum PipelineState: Equatable, Sendable {
    case idle
    case recording
    case processing(stage: ProcessingStage)
    case pendingInClipboard
    case error(PipelineError)

    enum ProcessingStage: String, Sendable {
        case transcribing, correcting, inserting
    }
}

struct PipelineError: Equatable, Sendable {
    let message: String
    let isRecoverable: Bool
}
```

---

## 1. HotkeyManager

Design: B+C Hybrid — Interface Segregation + AsyncStream + Toggle-Modus

```swift
struct HotkeyConfiguration: Sendable, Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt64
    var requiresHold: Bool  // true = Push-to-Talk, false = Toggle

    static let `default` = HotkeyConfiguration(
        keyCode: 0x3D, modifierFlags: 0, requiresHold: true
    )
}

enum HotkeyEvent: Sendable {
    case recordingStarted
    case recordingStopped
}

enum AccessibilityStatus: Sendable {
    case granted, denied, unknown
}

protocol HotkeyMonitoring: AnyObject, Sendable {
    var events: AsyncStream<HotkeyEvent> { get }
    var accessibilityStatus: AccessibilityStatus { get }
    var isHealthy: Bool { get }
    func start() async throws
    func stop()
    func suspend()
    func resume()
}

protocol HotkeyConfiguring: AnyObject, Sendable {
    var currentConfiguration: HotkeyConfiguration { get }
    func updateConfiguration(_ configuration: HotkeyConfiguration)
    func captureNextKeyPress(timeout: Duration) async -> HotkeyConfiguration?
}

protocol AccessibilityChecking: Sendable {
    func isAccessibilityGranted() -> Bool
    func requestAccessibility(prompt: Bool) -> Bool
}
```

Decisions:
- AsyncStream statt Combine (passt in async Pipeline)
- Toggle-Modus (requiresHold) von Anfang an mitgedacht
- isHealthy Property für CGEvent-Tap-Überwachung
- captureNextKeyPress für Settings-UI ("Drücke jetzt die gewünschte Taste")
- AccessibilityChecking als injizierbares Protocol für Tests

---

## 2. AudioRecorder

Design: B+C Hybrid — 3 Concerns + eigene Chunk-Typen

```swift
struct AudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Int           // 16000
    let timestamp: TimeInterval
    let duration: TimeInterval
    let level: AudioLevel
}

struct AudioLevel: Sendable {
    let average: Float            // 0.0...1.0
    let peak: Float
    let timestamp: TimeInterval
}

struct AudioDevice: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool
}

enum AudioRecorderError: Error, Sendable {
    case microphoneAccessDenied
    case deviceNotFound(deviceID: String)
    case deviceLost                       // USB-Mic abgezogen — Stream endet sauber, bisheriges Audio bleibt erhalten
    case engineSetupFailed(underlying: Error)
}

protocol AudioCapturing: AnyObject, Sendable {
    var audioStream: AsyncThrowingStream<AudioChunk, Error> { get }
    var state: AudioRecorderState { get }
    func startRecording() async throws
    func stopRecording() async
}

protocol AudioLevelMetering: AnyObject, Sendable {
    var levelStream: AsyncStream<AudioLevel> { get }
    func startMetering() async
    func stopMetering() async
}

protocol AudioDeviceManaging: AnyObject, Sendable {
    var availableDevices: AsyncStream<[AudioDevice]> { get }
    var selectedDevice: AudioDevice? { get }
    func selectDevice(_ device: AudioDevice) async throws
    func selectDefaultDevice() async throws
}

protocol AudioRecording: AudioCapturing, AudioLevelMetering, AudioDeviceManaging {}
```

Decisions:
- Eigene Typen statt AVFoundation im Interface ([Float] statt AVAudioPCMBuffer)
- 3 getrennte Protocols: Pipeline braucht nur AudioCapturing, UI nur AudioLevelMetering, Settings nur AudioDeviceManaging
- deviceLost: Stream endet sauber, bisheriges Audio wird noch transkribiert
- Keine AVFoundation-Abhängigkeit im Interface

---

## 3. TranscriptionEngine

Design: A+C Hybrid — Stream-in/out + loadModel + Closure-Injection

```swift
struct TranscriptionConfig: Sendable {
    var language: SupportedLanguage = .de
    var initialPrompt: String = ""       // Persönliches Wörterbuch
}

struct PartialTranscription: Sendable {
    let text: String
    let confidence: Float
}

struct FinalTranscription: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let processingTime: Duration
}

struct TranscriptionSegment: Sendable {
    let text: String
    let range: Range<Duration>
    let confidence: Float
}

enum TranscriptionResult: Sendable {
    case partial(PartialTranscription)
    case final(FinalTranscription)
}

enum TranscriptionLanguage: String, Sendable {
    case german = "de"
    case english = "en"
}

enum TranscriptionError: Error, Sendable {
    case modelNotLoaded
    case modelLoadFailed(underlying: Error)
    case streamingFailed(reason: String)
    case batchFailed(reason: String)
    case cancelled
}

protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audioChunks: AsyncStream<AudioChunk>,
        config: TranscriptionConfig
    ) -> AsyncStream<TranscriptionResult>

    func loadModel(
        for language: TranscriptionLanguage,
        onProgress: @Sendable (Double) -> Void
    ) async throws

    func cancel()
}
```

Concrete class uses constructor injection for testability:
```swift
final class WhisperTranscriptionEngine: TranscriptionEngine {
    init(
        streamStrategy: @Sendable ([Float], TranscriptionConfig) async throws -> String,
        batchStrategy: @Sendable ([Float], TranscriptionConfig) async throws -> String
    ) { ... }
}
```

Decisions:
- Stream-in → Stream-out (eine transcribe-Methode)
- AudioChunk.isFinal flag signals end of recording
- loadModel separate (App-Start), with progress callback for UI
- Streaming→Batch Fallback intern, unsichtbar für Caller
- Testbar über Closure-Injection (streamStrategy/batchStrategy), nicht über extra Protocols

---

## 4. TextCorrector

Design: B+C Hybrid — CorrectionOutcome Enum + Closure-Injection

```swift
struct CorrectionConfig: Sendable {
    var contextMode: ContextMode = .neutral
    var intensity: CorrectionIntensity = .init()
    var personalDictionary: [String] = []
    var timeoutMs: Int = 800
    var maxRetries: Int = 1
}

struct CorrectionStats: Sendable {
    let latencyMs: Int
    let tokensUsed: Int
    let wasRetry: Bool
}

enum FallbackReason: Sendable {
    case apiError(underlying: Error)
    case timeout
    case retryExhausted
    case emptyResponse
}

enum CorrectionOutcome: Sendable {
    case corrected(text: String, stats: CorrectionStats)
    case fallbackRaw(text: String, reason: FallbackReason)
}

struct DebugSnapshot: Sendable {
    let request: String
    let response: String?
    let outcome: CorrectionOutcome
    let timestamp: Date
}

protocol TextCorrecting: Sendable {
    func correct(_ input: TranscriptionResult) async -> CorrectionOutcome
    func updateConfig(_ config: CorrectionConfig)
    var lastDebugSnapshot: DebugSnapshot? { get }
}
```

Concrete class uses constructor injection:
```swift
final class TextCorrector: TextCorrecting {
    init(
        config: CorrectionConfig,
        transport: @Sendable (String, String, Int) async throws -> String,
        apiKeyProvider: @Sendable () throws -> String
    ) { ... }
}
```

Decisions:
- CorrectionOutcome Enum statt Bool — Caller weiß WARUM Fallback (timeout/network/empty)
- correct() wirft nie, liefert immer Text (korrigiert oder raw)
- Sprache kommt aus TranscriptionResult (nicht aus Config)
- tokensUsed für API-Kosten-Tracking
- Notification bei Fallback liegt beim Caller (Pipeline), nicht im Corrector

---

## 5. TextInserter

Design: A+B+C Hybrid — non-throwing + 4 Sub-Concerns + pendingInClipboard

```swift
struct ActiveApp: Sendable {
    let bundleIdentifier: String
    let localizedName: String
}

enum InsertionMethod: Sendable {
    case clipboard, accessibility
}

enum InsertionOutcome: Sendable {
    case inserted(method: InsertionMethod)
    case pendingInClipboard                // Text liegt bereit, User muss Cmd+V drücken
}

struct InsertionResult: Sendable {
    let outcome: InsertionOutcome
    let targetApp: ActiveApp?
    let clipboardRestored: Bool
}

protocol TextInserting: Sendable {
    func insert(_ text: String) async -> InsertionResult
}

protocol ActiveAppDetecting: Sendable {
    func frontmostApp() -> ActiveApp?
}

// Interne Sub-Concerns (Constructor Injection):
protocol ClipboardManaging: Sendable {
    func backup() async throws -> ClipboardSnapshot
    func set(text: String) async throws
    func restore(from snapshot: ClipboardSnapshot) async throws
}

protocol KeystrokeSimulating: Sendable {
    func simulatePaste() async throws
}

protocol AccessibilityInserting: Sendable {
    func insertViaAccessibility(text: String) async throws
}
```

Concrete class:
```swift
final class TextInserter: TextInserting {
    init(
        clipboard: ClipboardManaging,
        keystroke: KeystrokeSimulating,
        accessibility: AccessibilityInserting,
        appDetector: ActiveAppDetecting,
        restoreDelay: Duration = .milliseconds(80)
    ) { ... }
}
```

Decisions:
- insert() wirft NIE — immer InsertionResult zurück
- InsertionOutcome.pendingInClipboard wenn kein Textfeld erkannt (Heuristik: AXFocusedUIElement prüfen)
- Bei pendingInClipboard: Clipboard wird NICHT restored bis zum nächsten Diktat
- restoreDelay als Duration-Parameter für Tests (.zero in Tests)
- ActiveAppDetecting separat — wird auch vom Auto-Kontext-Modus gebraucht
- Prüft vor Paste ob Ziel-App ein Textfeld hat (AXFocusedUIElement)

---

## 6. DictationPipeline

Design: @Observable konkrete Klasse mit Dependencies-Container

```swift
struct PipelineDependencies {
    let hotkey: HotkeyMonitoring
    let recorder: AudioCapturing
    let metering: AudioLevelMetering
    let transcriber: TranscriptionEngine
    let corrector: TextCorrecting
    let inserter: TextInserting
    let appDetector: ActiveAppDetecting
    let store: DictationStoring
    let sound: SoundPlaying
}

@Observable
@MainActor
final class DictationPipeline {
    private(set) var state: PipelineState = .idle
    private(set) var audioLevel: Float = 0
    private(set) var streamingText: String = ""
    private(set) var lastError: PipelineError?
    private(set) var latencyMs: Int?

    init(dependencies: PipelineDependencies) { ... }

    // Hotkey-getriebener Hauptflow:
    func activate() async throws { ... }
    func deactivate() { ... }

    // Programmatischer Trigger (Button):
    func startDictation() async { ... }
    func stopDictation() async { ... }

    func cancelDictation() { ... }
    func dismissError() { ... }
}
```

Decisions:
- @Observable (nicht ObservableObject) — modern, feingranulare SwiftUI-Updates
- Konkrete Klasse statt Protocol — Testbarkeit über Dependency-Mocks
- PipelineDependencies Container statt 9 einzelne init-Parameter
- Sowohl Hotkey-getrieben (activate) als auch programmatisch (startDictation)
- Rapid Re-Dictation: Vorheriges Diktat läuft im Hintergrund weiter, neues startet sofort
- pendingInClipboard → macOS Notification, Clipboard-Restore erst beim nächsten Diktat
- Setup-Assistent beim ersten Start (4 Schritte: Mikrofon, Accessibility, API-Key, Modell)

---

## 7. DictationStore

Design: SwiftData @Query in Views + Protocol für Schreiben

```swift
import SwiftData

@Model
final class DictationRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawTranscript: String
    var correctedText: String
    var language: String
    var contextMode: String
    var targetApp: String?
    var durationMs: Int
    var processingTimeMs: Int

    var wordCount: Int { correctedText.split(separator: " ").count }
    var wordsPerMinute: Double {
        guard durationMs > 0 else { return 0 }
        return Double(wordCount) / (Double(durationMs) / 60_000)
    }
}

struct DictationStatistics: Sendable, Equatable {
    let totalCount: Int
    let todayCount: Int
    let weekCount: Int
    let totalWords: Int
    let averageWPM: Double
    let currentStreakDays: Int
    let averageProcessingTimeMs: Double
}

protocol DictationStoring: Sendable {
    func save(_ record: DictationRecord) throws
    func delete(_ record: DictationRecord) throws
    func statistics() -> DictationStatistics
    func updateHistoryLimit(_ limit: Int) throws  // trimmt sofort wenn nötig
}
```

Decisions:
- Views lesen via @Query direkt aus SwiftData (kein Store-Durchgriff für Lesen)
- DictationStoring Protocol nur für Schreiben + Statistiken (mockbar für Pipeline-Tests)
- updateHistoryLimit trimmt sofort — UI sollte User vorher warnen
- Volltextsuche via .filter in Views (Table-Scan bei 100 Records irrelevant)
- DictationRecord als @Model — Views sind an SwiftData gekoppelt (akzeptabel)

---

## 8. SettingsManager

Design: Gruppierte Structs + @Observable

```swift
struct AudioSettings: Codable, Equatable {
    var microphoneID: String? = nil
    var language: SupportedLanguage = .de
    var soundsEnabled: Bool = true
}

struct HotkeySettings: Codable, Equatable {
    var keyCode: UInt16 = 0x3D
    var modifierFlags: UInt64 = 0
    var requiresHold: Bool = true
}

struct CorrectionSettings: Codable, Equatable {
    var contextMode: ContextMode = .neutral
    var appMapping: [String: ContextMode] = [:]
    var allowRephrasing: Bool = false
    var allowShortening: Bool = false
    var allowRestructuring: Bool = false
    var personalDictionary: [String] = []
    var llmTimeoutMs: Int = 800
}

struct SystemSettings: Codable, Equatable {
    var autoStart: Bool = false
    var historyLimit: Int = 100
    var debugMode: Bool = false
}

enum APIKeyStatus: Equatable, Sendable {
    case missing, validating, valid, invalid(String)
}

protocol KeychainServiceProtocol: Sendable {
    func store(_ value: String, for account: String) throws
    func retrieve(for account: String) throws -> String
    func delete(for account: String) throws
}

@Observable
final class SettingsManager {
    var audio: AudioSettings       { didSet { persist(\.audio) } }
    var hotkey: HotkeySettings     { didSet { persist(\.hotkey) } }
    var correction: CorrectionSettings { didSet { persist(\.correction) } }
    var system: SystemSettings     { didSet { persist(\.system) } }

    private(set) var apiKeyStatus: APIKeyStatus = .missing

    func resolveAPIKey() throws -> String { ... }
    func setAPIKey(_ key: String) throws { ... }
    func deleteAPIKey() throws { ... }
    func validateAPIKey() async { ... }

    init(defaults: UserDefaults = .standard, keychain: KeychainServiceProtocol = KeychainService.shared)
}
```

Decisions:
- 4 gruppierte Structs (Audio, Hotkey, Correction, System) — 1:1 Mapping zu Settings-UI-Tabs
- @Observable + didSet = automatische Persistierung + SwiftUI-Updates
- Tiefe Bindings: $settings.audio.language funktioniert
- API-Key NICHT als bindbare Property — nur via resolveAPIKey()
- apiKeyStatus für Menu-Bar-Warnung und Onboarding
- Keychain als injizierbares Protocol für Tests

---

## 9. UI Layer

Design: macOS Scenes + MenuBarExtra + selektive Container/Presentational

```swift
@main struct DerFlüstererApp: App {
    @State private var pipeline: DictationPipeline
    @State private var settings: SettingsManager

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()        // Status, letzte 3 Diktate (One-Click-Copy), Quick-Toggles
        } label: {
            MenuBarIconView(state:audioLevel:hasAPIKeyIssue:)
        }
        .menuBarExtraStyle(.window)

        Window("DerFlüsterer", id: "main") { MainWindowView() }
        Settings { SettingsView() }      // ⌘, nativ
        Window("Setup", id: "setup") { SetupAssistantView() }
    }
}

// Menu Bar
struct MenuBarIconView: View              // Presentational: state, audioLevel, hasAPIKeyIssue
struct WaveformBarsView: View             // 3 Balken, Timer-basiert 15fps nur bei recording
struct MenuBarPopoverView: View           // Status + letzte 3 Diktate + Quick-Toggles

// Hauptfenster
struct MainWindowView: View               // TabView: History, Statistiken
struct HistoryTabView: View               // @Query direkt, durchsuchbar, löschbar, Klick kopiert
struct StatisticsTabView: View            // Presentational mit Snapshot-Struct

// Settings (eigene Scene)
struct SettingsView: View                 // TabView mit Sub-Panes
struct AudioSettingsPane: View
struct HotkeySettingsPane: View
struct CorrectionSettingsPane: View
struct SystemSettingsPane: View
struct APIKeySettingsPane: View

// Setup-Assistent
struct SetupAssistantView: View           // 4 Steps: Mikrofon, Accessibility, API-Key, Modell-Download
```

Decisions:
- MenuBarExtra mit .window Style für Popover
- Waveform via Timer (15fps), nur aktiv bei recording
- Settings als eigene macOS Scene (⌘, funktioniert nativ)
- Setup-Assistent als eigenes Window beim ersten Start
- MenuBarPopover: letzte 3 Diktate mit One-Click-Copy-Button
- Notifications via UNUserNotificationCenter bei pendingInClipboard
- @Query direkt in HistoryTabView (kein ViewModel nötig)
- Statistiken als Presentational View mit Snapshot-Struct
