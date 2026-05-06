import XCTest
@testable import Kalizap

final class ModuleProtocolTests: XCTestCase {

    func testAllProtocolsExist() {
        // This test verifies that all module protocols compile.
        // If any protocol is missing, this file won't compile → RED.
        func assertProtocolExists<T>(_ type: T.Type) {}

        assertProtocolExists(HotkeyMonitoring.self)
        assertProtocolExists(HotkeyConfiguring.self)
        assertProtocolExists(AccessibilityChecking.self)
        assertProtocolExists(AudioCapturing.self)
        assertProtocolExists(AudioLevelMetering.self)
        assertProtocolExists(AudioDeviceManaging.self)
        assertProtocolExists((any TranscriptionEngine).self)
        assertProtocolExists((any TextCorrecting).self)
        assertProtocolExists((any TextInserting).self)
        assertProtocolExists((any ActiveAppDetecting).self)
        assertProtocolExists((any ClipboardManaging).self)
        assertProtocolExists((any KeystrokeSimulating).self)
        assertProtocolExists((any AccessibilityInserting).self)
        assertProtocolExists((any DictationStoring).self)
    }
}
