import XCTest
@testable import DerFluisterer

final class SettingsVisibilityTests: XCTestCase {

    // MARK: - showAppMapping

    func testAppMappingVisibleOnlyForAutoAndLLMEnabled() {
        XCTAssertTrue(SettingsVisibility.showAppMapping(contextMode: .auto, isLLMEnabled: true))
    }

    func testAppMappingHiddenForNonAutoModes() {
        XCTAssertFalse(SettingsVisibility.showAppMapping(contextMode: .formal, isLLMEnabled: true))
        XCTAssertFalse(SettingsVisibility.showAppMapping(contextMode: .informal, isLLMEnabled: true))
        XCTAssertFalse(SettingsVisibility.showAppMapping(contextMode: .neutral, isLLMEnabled: true))
    }

    func testAppMappingHiddenWhenLLMDisabledEvenInAuto() {
        XCTAssertFalse(SettingsVisibility.showAppMapping(contextMode: .auto, isLLMEnabled: false))
    }

    // MARK: - showDebugSections

    func testDebugSectionsFollowFlag() {
        XCTAssertTrue(SettingsVisibility.showDebugSections(debugMode: true))
        XCTAssertFalse(SettingsVisibility.showDebugSections(debugMode: false))
    }

    // MARK: - styleControlsEnabled

    func testStyleControlsMirrorLLMState() {
        XCTAssertTrue(SettingsVisibility.styleControlsEnabled(isLLMEnabled: true))
        XCTAssertFalse(SettingsVisibility.styleControlsEnabled(isLLMEnabled: false))
    }
}
