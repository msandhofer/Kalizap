import XCTest
@testable import DerFluisterer

final class SemanticVersionTests: XCTestCase {

    func test_init_parsesPlainVersion() {
        let v = SemanticVersion("0.1.0")
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 1)
        XCTAssertEqual(v?.patch, 0)
    }

    func test_init_parsesWithVPrefix() {
        let v = SemanticVersion("v1.2.3")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func test_init_ignoresPreReleaseSuffix() {
        let v = SemanticVersion("1.2.3-beta.1")
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func test_init_returnsNilForMalformed() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion(""))
    }

    func test_compare_majorDominates() {
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.999.999")!)
    }

    func test_compare_minorDominates() {
        XCTAssertTrue(SemanticVersion("1.2.0")! > SemanticVersion("1.1.999")!)
    }

    func test_compare_patchDominates() {
        XCTAssertTrue(SemanticVersion("1.2.3")! > SemanticVersion("1.2.2")!)
    }

    func test_compare_equalVersions() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion("v1.2.3"))
    }

    func test_compare_stringLexBug() {
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)
    }
}
