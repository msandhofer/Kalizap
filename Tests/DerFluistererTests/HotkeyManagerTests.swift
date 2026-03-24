import XCTest
@testable import DerFluisterer

final class HotkeyConfigurationTests: XCTestCase {

    func test_defaultConfiguration_isRightOptionKeyHold() {
        let config = HotkeyConfiguration.default

        XCTAssertEqual(config.keyCode, 0x3D)       // right Option
        XCTAssertEqual(config.modifierFlags, 0)
        XCTAssertTrue(config.requiresHold)           // Push-to-Talk
    }

    func test_configuration_codableRoundTrip() throws {
        let original = HotkeyConfiguration(keyCode: 0x38, modifierFlags: 256, requiresHold: false)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}

// MARK: - Event Dispatch (Push-to-Talk)

@MainActor
final class HotkeyEventDispatchTests: XCTestCase {

    func test_pushToTalk_keyDown_emitsRecordingStarted() async {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
                if collected.count == 1 { break }
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3D)

        await task.value
        XCTAssertEqual(collected, [.recordingStarted])
    }

    func test_pushToTalk_keyDownThenKeyUp_emitsStartedThenStopped() async {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
                if collected.count == 2 { break }
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)

        await task.value
        XCTAssertEqual(collected, [.recordingStarted, .recordingStopped])
    }

    func test_pushToTalk_wrongKey_emitsNothing() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3A)  // left Option, not right
        dispatcher.handleKeyUp(keyCode: 0x3A)
        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertTrue(collected.isEmpty)
    }

    func test_pushToTalk_repeatedKeyDown_emitsOnlyOneStarted() async {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
                if collected.count == 2 { break }
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyDown(keyCode: 0x3D)  // key repeat
        dispatcher.handleKeyUp(keyCode: 0x3D)

        await task.value
        XCTAssertEqual(collected, [.recordingStarted, .recordingStopped])
    }
}

// MARK: - Toggle Mode

@MainActor
final class HotkeyToggleModeTests: XCTestCase {

    private let toggleConfig = HotkeyConfiguration(keyCode: 0x3D, modifierFlags: 0, requiresHold: false)

    func test_toggleMode_firstKeyDown_startsRecording() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: toggleConfig)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)
        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertEqual(collected, [.recordingStarted])
    }

    func test_toggleMode_secondKeyDown_stopsRecording() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: toggleConfig)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)
        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertEqual(collected, [.recordingStarted, .recordingStopped])
    }
}

// MARK: - Suspend/Resume

@MainActor
final class HotkeySuspendResumeTests: XCTestCase {

    func test_suspendedDispatcher_ignoresKeyEvents() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        dispatcher.suspend()
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)
        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertTrue(collected.isEmpty)
    }

    func test_resumeAfterSuspend_firesEventsAgain() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: .default)
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        dispatcher.suspend()
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)

        dispatcher.resume()
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)
        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertEqual(collected, [.recordingStarted, .recordingStopped])
    }
}

// MARK: - Configuration Update

@MainActor
final class HotkeyConfigUpdateTests: XCTestCase {

    func test_updateConfiguration_newKeyCodeIsUsed() async throws {
        let dispatcher = HotkeyEventDispatcher(configuration: .default) // 0x3D
        var collected: [HotkeyEvent] = []

        let task = Task {
            for await event in dispatcher.events {
                collected.append(event)
            }
        }

        // Old key should work
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)

        // Update to new key
        dispatcher.updateConfiguration(HotkeyConfiguration(keyCode: 0x38, modifierFlags: 0, requiresHold: true))

        // Old key should no longer work
        dispatcher.handleKeyDown(keyCode: 0x3D)
        dispatcher.handleKeyUp(keyCode: 0x3D)

        // New key should work
        dispatcher.handleKeyDown(keyCode: 0x38)
        dispatcher.handleKeyUp(keyCode: 0x38)

        try await Task.sleep(for: .milliseconds(50))
        dispatcher.finish()

        await task.value
        XCTAssertEqual(collected, [.recordingStarted, .recordingStopped, .recordingStarted, .recordingStopped])
    }
}
