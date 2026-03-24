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

    func play(_ sound: SoundEffect) {
        playedSounds.append(sound)
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
