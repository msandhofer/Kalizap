import XCTest
@testable import DerFluisterer

final class HomebrewDetectorTests: XCTestCase {

    private final class FakeFileExistenceChecker: FileExistenceChecking, @unchecked Sendable {
        var existingPaths: Set<String> = []
        func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }
    }

    func test_detect_noBrewInstalled_returnsNotInstalled() {
        let fake = FakeFileExistenceChecker()
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .notInstalled)
    }

    func test_detect_brewArmInstalled_notViaCask_returnsDirectDownload() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/opt/homebrew/bin/brew"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedDirectDownload)
    }

    func test_detect_brewIntelInstalled_notViaCask_returnsDirectDownload() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/usr/local/bin/brew"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedDirectDownload)
    }

    func test_detect_brewArmAndCaskroom_returnsInstalledViaCask() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/derfluesterer"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedViaCask)
    }

    func test_detect_brewIntelAndCaskroom_returnsInstalledViaCask() {
        let fake = FakeFileExistenceChecker()
        fake.existingPaths = ["/usr/local/bin/brew", "/usr/local/Caskroom/derfluesterer"]
        let sut = HomebrewDetector(fileExistence: fake)
        XCTAssertEqual(sut.detect(), .installedViaCask)
    }
}
