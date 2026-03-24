import Foundation

public struct AudioSettings: Codable, Equatable {
    public var microphoneID: String? = nil
    public var language: SupportedLanguage = .de
    public var soundsEnabled: Bool = true
    public init(microphoneID: String? = nil, language: SupportedLanguage = .de, soundsEnabled: Bool = true) {
        self.microphoneID = microphoneID
        self.language = language
        self.soundsEnabled = soundsEnabled
    }
}

public struct HotkeySettings: Codable, Equatable {
    public var keyCode: UInt16 = 0x3D
    public var modifierFlags: UInt64 = 0
    public var requiresHold: Bool = true
    public init(keyCode: UInt16 = 0x3D, modifierFlags: UInt64 = 0, requiresHold: Bool = true) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.requiresHold = requiresHold
    }
}

public struct CorrectionSettings: Codable, Equatable {
    public var contextMode: ContextMode = .neutral
    public var appMapping: [String: ContextMode] = CorrectionSettings.defaultAppMapping
    public var allowRephrasing: Bool = false
    public var allowShortening: Bool = false
    public var allowRestructuring: Bool = false
    public var personalDictionary: [String] = []
    public var llmTimeoutMs: Int = 800
    public static let defaultAppMapping: [String: ContextMode] = [
        "com.apple.mail": .formal,
        "com.tinyspeck.slackmacgap": .informal,
        "com.microsoft.Outlook": .formal
    ]
    public init(contextMode: ContextMode = .neutral, appMapping: [String: ContextMode] = CorrectionSettings.defaultAppMapping, allowRephrasing: Bool = false, allowShortening: Bool = false, allowRestructuring: Bool = false, personalDictionary: [String] = [], llmTimeoutMs: Int = 800) {
        self.contextMode = contextMode
        self.appMapping = appMapping
        self.allowRephrasing = allowRephrasing
        self.allowShortening = allowShortening
        self.allowRestructuring = allowRestructuring
        self.personalDictionary = personalDictionary
        self.llmTimeoutMs = llmTimeoutMs
    }
}

public struct SystemSettings: Codable, Equatable {
    public var autoStart: Bool = false
    public var historyLimit: Int = 100
    public var debugMode: Bool = false
    public init(autoStart: Bool = false, historyLimit: Int = 100, debugMode: Bool = false) {
        self.autoStart = autoStart
        self.historyLimit = historyLimit
        self.debugMode = debugMode
    }
}

public enum APIKeyStatus: Equatable, Sendable {
    case missing, validating, valid, invalid(String)
}

public protocol KeychainServiceProtocol: Sendable {
    func store(_ value: String, for account: String) throws
    func retrieve(for account: String) throws -> String
    func delete(for account: String) throws
}

public protocol APIKeyValidating: Sendable {
    func validate(apiKey: String) async throws
}

public protocol LaunchAtLoginProtocol: Sendable {
    func register() throws
    func unregister() throws
}

public struct NoOpLaunchAtLogin: LaunchAtLoginProtocol {
    public init() {}
    public func register() throws {}
    public func unregister() throws {}
}

@Observable @MainActor
public final class SettingsManager {
    public var audio: AudioSettings { didSet { persist(audio, forKey: "audio") } }
    public var hotkey: HotkeySettings { didSet { persist(hotkey, forKey: "hotkey") } }
    public var correction: CorrectionSettings { didSet { persist(correction, forKey: "correction") } }
    public var system: SystemSettings { didSet { persist(system, forKey: "system") } }

    public private(set) var apiKeyStatus: APIKeyStatus = .missing

    private let defaults: UserDefaults
    private let keychain: any KeychainServiceProtocol
    private let apiKeyValidator: any APIKeyValidating
    private let launchAtLogin: any LaunchAtLoginProtocol

    public init(defaults: UserDefaults = .standard, keychain: any KeychainServiceProtocol, apiKeyValidator: any APIKeyValidating, launchAtLogin: any LaunchAtLoginProtocol = NoOpLaunchAtLogin()) {
        self.defaults = defaults
        self.keychain = keychain
        self.apiKeyValidator = apiKeyValidator
        self.launchAtLogin = launchAtLogin
        self.audio = Self.load(from: defaults, forKey: "audio") ?? AudioSettings()
        self.hotkey = Self.load(from: defaults, forKey: "hotkey") ?? HotkeySettings()
        self.correction = Self.load(from: defaults, forKey: "correction") ?? CorrectionSettings()
        self.system = Self.load(from: defaults, forKey: "system") ?? SystemSettings()
    }

    private static let apiKeyAccount = "anthropic-api-key"

    public func setAPIKey(_ key: String) throws {
        try keychain.store(key, for: Self.apiKeyAccount)
    }

    public func resolveAPIKey() throws -> String {
        try keychain.retrieve(for: Self.apiKeyAccount)
    }

    public func deleteAPIKey() throws {
        try keychain.delete(for: Self.apiKeyAccount)
        apiKeyStatus = .missing
    }

    public func setAutoStart(_ enabled: Bool) throws {
        if enabled {
            try launchAtLogin.register()
        } else {
            try launchAtLogin.unregister()
        }
        system.autoStart = enabled
    }

    public func validateAPIKey() async {
        guard let key = try? resolveAPIKey() else {
            apiKeyStatus = .missing
            return
        }
        apiKeyStatus = .validating
        do {
            try await apiKeyValidator.validate(apiKey: key)
            apiKeyStatus = .valid
        } catch {
            apiKeyStatus = .invalid(error.localizedDescription)
        }
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
