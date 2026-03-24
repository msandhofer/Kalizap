import Foundation

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
