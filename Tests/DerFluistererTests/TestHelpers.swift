import Foundation
@testable import DerFluisterer

// MARK: - Sendable Test Helpers

final class SendableBox<T>: @unchecked Sendable {
    private(set) var value: T
    init(_ value: T) { self.value = value }
    func set(_ newValue: T) { value = newValue }
}

// MARK: - Shared Mocks

final class MockSoundBackend: SoundBackend, @unchecked Sendable {
    var playedSounds: [SoundEffect] = []
    var prewarmCallCount = 0

    func play(_ sound: SoundEffect) {
        playedSounds.append(sound)
    }

    func prewarm() {
        prewarmCallCount += 1
    }
}

// MARK: - AudioActivityMonitor Mock

final class MockAudioActivityMonitor: AudioActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var warm: Bool

    init(warm: Bool = true) {
        self.warm = warm
    }

    func isAudioWarm() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return warm
    }

    func setWarm(_ value: Bool) {
        lock.lock()
        warm = value
        lock.unlock()
    }
}

// MARK: - TextInserter Mocks

final class MockClipboardManager: ClipboardManaging, @unchecked Sendable {
    var backedUp = false
    var restoredSnapshot: ClipboardSnapshot?
    var setText: String?
    var backupError: (any Error)?
    var setError: (any Error)?
    var restoreError: (any Error)?

    func backup() async throws -> ClipboardSnapshot {
        if let backupError { throw backupError }
        backedUp = true
        return ClipboardSnapshot(data: Data("original".utf8))
    }

    func set(text: String) async throws {
        if let setError { throw setError }
        setText = text
    }

    func restore(from snapshot: ClipboardSnapshot) async throws {
        if let restoreError { throw restoreError }
        restoredSnapshot = snapshot
    }
}

final class MockKeystrokeSimulator: KeystrokeSimulating, @unchecked Sendable {
    var pasteSimulated = false
    var simulateError: (any Error)?

    func simulatePaste() async throws {
        if let simulateError { throw simulateError }
        pasteSimulated = true
    }
}

final class MockAccessibilityInserter: AccessibilityInserting, @unchecked Sendable {
    var hasTextField: Bool
    var insertedText: String?
    var insertError: (any Error)?

    init(hasTextField: Bool = true) {
        self.hasTextField = hasTextField
    }

    func hasTextFieldFocus() -> Bool {
        hasTextField
    }

    func insertViaAccessibility(text: String) async throws {
        if let insertError { throw insertError }
        insertedText = text
    }
}

final class MockAudioSpectrumProvider: AudioSpectrumProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable ([Float]) -> Void)?

    func setSpectrumHandler(_ handler: (@Sendable ([Float]) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func emit(_ bands: [Float]) {
        lock.lock()
        let h = handler
        lock.unlock()
        h?(bands)
    }
}

final class MockAppDetector: ActiveAppDetecting, @unchecked Sendable {
    var app: ActiveApp?

    init(app: ActiveApp? = nil) {
        self.app = app
    }

    func frontmostApp() -> ActiveApp? {
        app
    }
}

// MARK: - Factory Helpers

func makeTestChunk(
    samples: [Float] = [0.1, 0.2, 0.3],
    sampleRate: Int = 16000,
    timestamp: TimeInterval = 0
) -> AudioChunk {
    let duration = Double(samples.count) / Double(sampleRate)
    let level = AudioLevelCalculator.calculate(from: samples, timestamp: timestamp)
    return AudioChunk(
        samples: samples,
        sampleRate: sampleRate,
        timestamp: timestamp,
        duration: duration,
        level: level
    )
}

func makeTestTranscriptionResult(_ text: String) -> TranscriptionResult {
    .final(FinalTranscription(
        text: text,
        segments: [],
        processingTime: .milliseconds(100)
    ))
}

func makeTestAudioStream(_ chunks: [AudioChunk]) -> AsyncStream<AudioChunk> {
    AsyncStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

// MARK: - Async Wait Helpers

/// Poll for an async condition until it returns true, or the timeout elapses.
/// Returns true on success, false on timeout. Stabilere Alternative zu hart
/// codierten Task.sleep-Waits in Tests: prüft die Bedingung alle paar ms und
/// kehrt zurück, sobald sie erfüllt ist — spart Zeit auf schnellen Rechnern,
/// schlägt deterministisch fehl auf langsamen.
@Sendable
func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: pollInterval)
    }
    return await condition()
}
