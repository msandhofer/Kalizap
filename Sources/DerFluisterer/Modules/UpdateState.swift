import Foundation

public enum UpdateMethod: Equatable, Sendable {
    case homebrewCask(command: String)
    case directDownload(url: URL)
}

public enum UpdateState: Equatable, Sendable {
    case unknown
    case noUpdate
    case available(version: String, method: UpdateMethod)
}
