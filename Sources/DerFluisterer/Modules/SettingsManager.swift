import Foundation

public struct AudioSettings: Codable, Equatable {
    public var microphoneID: String? = nil
    public var language: SupportedLanguage = .de
    public var soundsEnabled: Bool = true
    public var noiseSuppressionEnabled: Bool = true

    public init(microphoneID: String? = nil, language: SupportedLanguage = .de, soundsEnabled: Bool = true, noiseSuppressionEnabled: Bool = true) {
        self.microphoneID = microphoneID
        self.language = language
        self.soundsEnabled = soundsEnabled
        self.noiseSuppressionEnabled = noiseSuppressionEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        microphoneID = try container.decodeIfPresent(String.self, forKey: .microphoneID)
        language = try container.decodeIfPresent(SupportedLanguage.self, forKey: .language) ?? .de
        soundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        noiseSuppressionEnabled = try container.decodeIfPresent(Bool.self, forKey: .noiseSuppressionEnabled) ?? true
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

    public var displayName: String {
        HotkeyDisplayNames.name(forKeyCode: keyCode)
    }

    public var configuration: HotkeyConfiguration {
        HotkeyConfiguration(keyCode: keyCode, modifierFlags: modifierFlags, requiresHold: requiresHold)
    }
}

public enum HotkeyDisplayNames {
    public static let selectableKeys: [(name: String, keyCode: UInt16)] = [
        ("Right Option", 0x3D),
        ("Left Option", 0x3A),
        ("Right Command", 0x36),
        ("Right Shift", 0x3C),
        ("Right Control", 0x3E),
        ("F5", 0x60),
        ("F6", 0x61),
    ]

    private static let keyNames: [UInt16: String] = {
        var map: [UInt16: String] = [
            0x38: "Left Shift", 0x3B: "Left Control",
            0x37: "Left Command", 0x39: "Caps Lock",
            0x30: "Tab", 0x31: "Space", 0x24: "Return",
            0x33: "Delete", 0x35: "Escape",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x62: "F7", 0x64: "F8", 0x65: "F9",
            0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        for (name, code) in selectableKeys {
            map[code] = name
        }
        return map
    }()

    public static func name(forKeyCode keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key \(String(format: "0x%02X", keyCode))"
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
    public var showAPIKeyNotification: Bool = true

    public var taskGrammar: Bool = true
    public var taskFillerRemoval: Bool = true
    public var taskWrittenLanguage: Bool = true
    public var taskPunctuation: Bool = true
    public var taskPreventHallucination: Bool = true

    public static let defaultAppMapping: [String: ContextMode] = [
        "com.apple.mail": .formal,
        "com.tinyspeck.slackmacgap": .informal,
        "com.microsoft.Outlook": .formal
    ]

    public init(
        contextMode: ContextMode = .neutral,
        appMapping: [String: ContextMode] = CorrectionSettings.defaultAppMapping,
        allowRephrasing: Bool = false,
        allowShortening: Bool = false,
        allowRestructuring: Bool = false,
        personalDictionary: [String] = [],
        llmTimeoutMs: Int = 800,
        showAPIKeyNotification: Bool = true,
        taskGrammar: Bool = true,
        taskFillerRemoval: Bool = true,
        taskWrittenLanguage: Bool = true,
        taskPunctuation: Bool = true,
        taskPreventHallucination: Bool = true
    ) {
        self.contextMode = contextMode
        self.appMapping = appMapping
        self.allowRephrasing = allowRephrasing
        self.allowShortening = allowShortening
        self.allowRestructuring = allowRestructuring
        self.personalDictionary = personalDictionary
        self.llmTimeoutMs = llmTimeoutMs
        self.showAPIKeyNotification = showAPIKeyNotification
        self.taskGrammar = taskGrammar
        self.taskFillerRemoval = taskFillerRemoval
        self.taskWrittenLanguage = taskWrittenLanguage
        self.taskPunctuation = taskPunctuation
        self.taskPreventHallucination = taskPreventHallucination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextMode = try container.decodeIfPresent(ContextMode.self, forKey: .contextMode) ?? .neutral
        appMapping = try container.decodeIfPresent([String: ContextMode].self, forKey: .appMapping) ?? CorrectionSettings.defaultAppMapping
        allowRephrasing = try container.decodeIfPresent(Bool.self, forKey: .allowRephrasing) ?? false
        allowShortening = try container.decodeIfPresent(Bool.self, forKey: .allowShortening) ?? false
        allowRestructuring = try container.decodeIfPresent(Bool.self, forKey: .allowRestructuring) ?? false
        personalDictionary = try container.decodeIfPresent([String].self, forKey: .personalDictionary) ?? []
        llmTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .llmTimeoutMs) ?? 800
        showAPIKeyNotification = try container.decodeIfPresent(Bool.self, forKey: .showAPIKeyNotification) ?? true
        taskGrammar = try container.decodeIfPresent(Bool.self, forKey: .taskGrammar) ?? true
        taskFillerRemoval = try container.decodeIfPresent(Bool.self, forKey: .taskFillerRemoval) ?? true
        taskWrittenLanguage = try container.decodeIfPresent(Bool.self, forKey: .taskWrittenLanguage) ?? true
        taskPunctuation = try container.decodeIfPresent(Bool.self, forKey: .taskPunctuation) ?? true
        taskPreventHallucination = try container.decodeIfPresent(Bool.self, forKey: .taskPreventHallucination) ?? true
    }

    public var isLLMEnabled: Bool {
        taskGrammar || taskFillerRemoval || taskWrittenLanguage || taskPunctuation || taskPreventHallucination
    }

    public var tasks: CorrectionTasks {
        CorrectionTasks(
            grammar: taskGrammar,
            fillerRemoval: taskFillerRemoval,
            writtenLanguage: taskWrittenLanguage,
            punctuation: taskPunctuation,
            preventHallucination: taskPreventHallucination
        )
    }
}

public struct UpdateSettings: Codable, Equatable {
    public var autoCheckEnabled: Bool = true
    public var silentAutoUpdate: Bool = false
    public var lastSuccessfulUpdateCheck: Date? = nil
    public init(autoCheckEnabled: Bool = true, silentAutoUpdate: Bool = false, lastSuccessfulUpdateCheck: Date? = nil) {
        self.autoCheckEnabled = autoCheckEnabled
        self.silentAutoUpdate = silentAutoUpdate
        self.lastSuccessfulUpdateCheck = lastSuccessfulUpdateCheck
    }

    public var feedUnreachableWarning: String? {
        guard let lastCheck = lastSuccessfulUpdateCheck else { return nil }
        let daysSinceLastCheck = Calendar.current.dateComponents([.day], from: lastCheck, to: Date()).day ?? 0
        guard daysSinceLastCheck >= 30 else { return nil }
        return "Auto-Update-Server seit \(daysSinceLastCheck) Tagen nicht erreichbar"
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
    public var update: UpdateSettings { didSet { persist(update, forKey: "update") } }

    public let apiKey: APIKeyManager
    private let launchAtLogin: any LaunchAtLoginProtocol
    private let defaults: UserDefaults

    /// Convenience accessor for backward compatibility.
    public var apiKeyStatus: APIKeyStatus { apiKey.status }

    public init(defaults: UserDefaults = .standard, keychain: any KeychainServiceProtocol, apiKeyValidator: any APIKeyValidating, launchAtLogin: any LaunchAtLoginProtocol = NoOpLaunchAtLogin()) {
        self.defaults = defaults
        self.launchAtLogin = launchAtLogin
        self.apiKey = APIKeyManager(keychain: keychain, validator: apiKeyValidator)
        self.audio = Self.load(from: defaults, forKey: "audio") ?? AudioSettings()
        self.hotkey = Self.load(from: defaults, forKey: "hotkey") ?? HotkeySettings()
        self.correction = Self.load(from: defaults, forKey: "correction") ?? CorrectionSettings()
        self.system = Self.load(from: defaults, forKey: "system") ?? SystemSettings()
        self.update = Self.load(from: defaults, forKey: "update") ?? UpdateSettings()
    }

    // MARK: - Delegating API Key methods (backward compatibility)

    public func setAPIKey(_ key: String) throws {
        try apiKey.setKey(key)
    }

    public func resolveAPIKey() throws -> String {
        try apiKey.resolveKey()
    }

    nonisolated public func resolveAPIKeySendable() throws -> String {
        try apiKey.resolveKeySendable()
    }

    public func deleteAPIKey() throws {
        try apiKey.deleteKey()
    }

    public func validateAPIKey() async {
        await apiKey.validate()
    }

    // MARK: - Launch at Login

    public func setAutoStart(_ enabled: Bool) throws {
        if enabled {
            try launchAtLogin.register()
        } else {
            try launchAtLogin.unregister()
        }
        system.autoStart = enabled
    }

    public var feedUnreachableWarning: String? {
        update.feedUnreachableWarning
    }

    // MARK: - Persistence

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
