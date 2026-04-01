import Foundation

public struct Config: Codable {
    public var hotkey: HotkeyConfig
    public var modelPath: String?
    public var modelSize: String
    public var language: String
    public var spokenPunctuation: FlexBool?
    public var maxRecordings: Int?
    public var engine: String?  // "whisper" (default) or "gigaam"
    public var gigaamPath: String?  // path to gigaam-v3-ctc-mlx model directory
    public var soundFeedback: FlexBool?  // play sound on record start/stop (default: true)
    public var streaming: FlexBool?  // real-time transcription (default: true)
    public var postProcessingProvider: String?  // "none" (default) or "local-llm"
    public var postProcessingModelID: String?  // Hugging Face / mlx-community model id
    public var postProcessingModelPath: String?  // local path to MLX model directory
    public var postProcessingMaxTokens: Int?  // response token cap for local LLM cleanup
    public var postProcessingTemperature: Double?  // sampling temperature (default: 0)
    public var postProcessingTimeoutMs: Int?  // timeout for final cleanup pass

    public static let defaultMaxRecordings = 0

    public static func effectiveMaxRecordings(_ value: Int?) -> Int {
        let raw = value ?? Config.defaultMaxRecordings
        if raw == 0 { return 0 }
        return min(max(1, raw), 100)
    }

    public var effectiveEngine: String {
        return engine ?? "gigaam"
    }

    public var effectiveSoundFeedback: Bool {
        return soundFeedback?.value ?? true
    }

    public var effectiveStreaming: Bool {
        return streaming?.value ?? true
    }

    public var effectivePostProcessingProvider: String {
        let value = (postProcessingProvider ?? "none").lowercased()
        return ["none", "local-llm"].contains(value) ? value : "none"
    }

    public var effectivePostProcessingModelID: String {
        postProcessingModelID ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    }

    public var effectivePostProcessingMaxTokens: Int {
        min(max(postProcessingMaxTokens ?? 96, 1), 512)
    }

    public var effectivePostProcessingTemperature: Float {
        Float(postProcessingTemperature ?? 0)
    }

    public var effectivePostProcessingTimeoutMs: Int {
        min(max(postProcessingTimeoutMs ?? 1500, 100), 15_000)
    }

    public static let defaultConfig = Config(
        hotkey: HotkeyConfig(keyCode: 61, modifiers: []),
        modelPath: nil,
        modelSize: "base.en",
        language: "ru",
        spokenPunctuation: FlexBool(false),
        maxRecordings: nil,
        engine: "gigaam",
        gigaamPath: nil,
        soundFeedback: FlexBool(true),
        streaming: FlexBool(true),
        postProcessingProvider: nil,
        postProcessingModelID: nil,
        postProcessingModelPath: nil,
        postProcessingMaxTokens: nil,
        postProcessingTemperature: nil,
        postProcessingTimeoutMs: nil
    )

    /// Config directory in iCloud Drive (syncs across devices)
    public static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Dikto")
    }

    /// Local data directory for models, recordings, and other large files
    public static var dataDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Dikto")
    }

    private static var legacyConfigDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/RuWispr"),
            home.appendingPathComponent(".config/ru-wisper"),
            home.appendingPathComponent(".config/dikto"),
        ]
    }

    private static var legacyDataDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/RuWispr"),
            home.appendingPathComponent(".config/ru-wisper"),
            home.appendingPathComponent(".config/dikto"),
        ]
    }

    public static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    private static func migrateItem(
        from legacyDirs: [URL],
        relativePath: String,
        to destination: URL,
        destinationParent: URL,
        label: String
    ) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { return }

        for legacyDir in legacyDirs {
            let source = legacyDir.appendingPathComponent(relativePath)
            guard fm.fileExists(atPath: source.path) else { continue }

            do {
                try fm.createDirectory(at: destinationParent, withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: destination)
                fputs("Migrated \(label) to: \(destination.path)\n", stderr)
                return
            } catch {
                fputs("Warning: could not migrate \(label) from \(source.path): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Migrate from previous RuWispr paths and legacy ~/.config installs into Dikto paths.
    public static func migrateIfNeeded() {
        migrateItem(
            from: legacyConfigDirs,
            relativePath: "config.json",
            to: configFile,
            destinationParent: configDir,
            label: "config"
        )

        migrateItem(
            from: legacyDataDirs,
            relativePath: "models",
            to: dataDir.appendingPathComponent("models"),
            destinationParent: dataDir,
            label: "models"
        )

        migrateItem(
            from: legacyDataDirs,
            relativePath: "recordings",
            to: dataDir.appendingPathComponent("recordings"),
            destinationParent: dataDir,
            label: "recordings"
        )

        let fm = FileManager.default
        let legacyDirs = Array(Set((legacyConfigDirs + legacyDataDirs).map(\.path))).map(URL.init(fileURLWithPath:))
        for legacyDir in legacyDirs {
            guard fm.fileExists(atPath: legacyDir.path) else { continue }
            guard let contents = try? fm.contentsOfDirectory(atPath: legacyDir.path), contents.isEmpty else { continue }
            try? fm.removeItem(at: legacyDir)
            fputs("Removed empty legacy dir: \(legacyDir.path)\n", stderr)
        }
    }

    public static func load() -> Config {
        migrateIfNeeded()

        guard let data = try? Data(contentsOf: configFile) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }

        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            fputs("Warning: unable to parse \(configFile.path): \(error.localizedDescription)\n", stderr)
            return Config.defaultConfig
        }
    }

    public static func decode(from data: Data) throws -> Config {
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile)
    }
}

public struct FlexBool: Codable {
    public let value: Bool

    public init(_ value: Bool) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            value = b
        } else if let s = try? container.decode(String.self) {
            value = ["true", "yes", "1"].contains(s.lowercased())
        } else if let i = try? container.decode(Int.self) {
            value = i != 0
        } else {
            value = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct HotkeyConfig: Codable {
    public var keyCode: UInt16
    public var modifiers: [String]

    public init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: UInt64 {
        var flags: UInt64 = 0
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags |= UInt64(1 << 20)
            case "shift": flags |= UInt64(1 << 17)
            case "ctrl", "control": flags |= UInt64(1 << 18)
            case "opt", "option", "alt": flags |= UInt64(1 << 19)
            default: break
            }
        }
        return flags
    }
}
