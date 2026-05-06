import Foundation

public enum HomebrewStatus: Equatable, Sendable {
    case notInstalled
    case installedDirectDownload
    case installedViaCask
}

public protocol FileExistenceChecking: Sendable {
    func fileExists(atPath path: String) -> Bool
}

public struct ProductionFileExistenceChecker: FileExistenceChecking {
    public init() {}
    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

public struct HomebrewDetector: Sendable {
    private let fileExistence: any FileExistenceChecking

    private static let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private static let caskroomPaths = [
        "/opt/homebrew/Caskroom/kalizap",
        "/usr/local/Caskroom/kalizap",
    ]

    public init(fileExistence: any FileExistenceChecking = ProductionFileExistenceChecker()) {
        self.fileExistence = fileExistence
    }

    public func detect() -> HomebrewStatus {
        let brewInstalled = Self.brewPaths.contains(where: { fileExistence.fileExists(atPath: $0) })
        guard brewInstalled else { return .notInstalled }

        let viaCask = Self.caskroomPaths.contains(where: { fileExistence.fileExists(atPath: $0) })
        return viaCask ? .installedViaCask : .installedDirectDownload
    }
}
