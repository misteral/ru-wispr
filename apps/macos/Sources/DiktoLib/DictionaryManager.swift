import Foundation

/// Replaces transliterated tech terms with canonical spellings before pasting.
///
/// Mappings live in `dictionary.json` next to `config.json` so users can edit
/// them and have changes sync via iCloud. The shared instance loads the file
/// once on first access; transcription only walks the cached regex array.
public final class DictionaryManager: @unchecked Sendable {
    public static let shared = DictionaryManager()

    /// Compile-time fallback used when the app bundle's `dictionary.json` is
    /// unavailable (e.g. `swift test`, `swift run`, broken bundle). The shipped
    /// JSON file in `Resources/dictionary.json` is the source of truth — keep
    /// these two in sync (a unit test enforces this).
    public static let defaultDictionary: [String: String] = [
        "икс код": "Xcode",
        "визо студио": "Visual Studio",
        "рубин релс": "Ruby on Rails",
        "свифт": "Swift",
        "питон": "Python",
        "джава скрипт": "JavaScript",
        "джей эс": "JS",
        "рект": "React",
        "реакт": "React",
        "вю": "Vue",
        "постгрес": "PostgreSQL",
        "докер": "Docker",
        "кубернетес": "Kubernetes",
        "мак ос": "macOS",
        "апи": "API",
        "гетхаб": "GitHub",
        "гитхаб": "GitHub",
        "джейсон": "JSON",
    ]

    public static var dictionaryFile: URL {
        Config.configDir.appendingPathComponent("dictionary.json")
    }

    /// Default dictionary shipped inside the app bundle. Present in production
    /// builds (copied by build scripts into `Contents/Resources/`), absent
    /// in dev/test runs — callers must fall back to `defaultDictionary`.
    public static var bundledDefaultURL: URL? {
        Bundle.main.url(forResource: "dictionary", withExtension: "json")
    }

    /// Defaults to seed a new user file with: prefer the bundled JSON (lets
    /// users see hand-formatted output when they open the file), fall back to
    /// the hardcoded constant.
    private static func currentDefaults() -> [String: String] {
        if let url = bundledDefaultURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        return defaultDictionary
    }

    private struct Entry {
        let regex: Regex<AnyRegexOutput>
        let replacement: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    /// Test seam: build a manager directly from an in-memory dictionary.
    public init(dictionary: [String: String]) {
        entries = Self.compile(dictionary)
    }

    /// Default initializer: load from `dictionary.json`, seeding it with the
    /// default mappings on first use.
    public convenience init() {
        self.init(file: Self.dictionaryFile)
    }

    /// Test seam: load from an arbitrary file path (still seeds defaults if missing).
    public init(file: URL) {
        let dict = Self.loadFromDisk(at: file)
        entries = Self.compile(dict)
    }

    /// Replace every dictionary key in `text` with its mapped value.
    /// Matches are case-insensitive and bounded by Unicode word boundaries.
    public func apply(to text: String) -> String {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        var result = text
        for entry in snapshot {
            result = result.replacing(entry.regex, with: entry.replacement)
        }
        return result
    }

    /// Re-read the dictionary file. Useful if the user edits it at runtime.
    public func reload() {
        let dict = Self.loadFromDisk(at: Self.dictionaryFile)
        let compiled = Self.compile(dict)
        lock.lock()
        entries = compiled
        lock.unlock()
    }

    private static func loadFromDisk(at url: URL) -> [String: String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            try? writeDefault(to: url)
            return currentDefaults()
        }

        // File exists — try to parse. On failure, leave the user's file alone
        // (they may be mid-edit) and fall back to defaults in memory. Surface
        // the underlying error so users can tell apart "syntax error on line N"
        // from "iCloud placeholder not yet downloaded" from "permission denied".
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            fputs("Warning: unable to parse \(url.path) (\(error.localizedDescription)); using default dictionary\n", stderr)
            return currentDefaults()
        }
    }

    /// Seed a new user dictionary file. Prefer copying the bundled JSON so the
    /// user opens a hand-formatted file (sorted, easy to extend); fall back to
    /// encoder output when running outside of an app bundle.
    private static func writeDefault(to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if let bundled = bundledDefaultURL,
           let data = try? Data(contentsOf: bundled) {
            try data.write(to: url)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(defaultDictionary)
        try data.write(to: url)
    }

    private static func compile(_ dictionary: [String: String]) -> [Entry] {
        // Sort by descending key length so longer phrases ("джава скрипт")
        // match before shorter prefixes that might overlap.
        let sorted = dictionary.sorted { $0.key.count > $1.key.count }
        return sorted.compactMap { (key, value) in
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "\\b" + escaped + "\\b"
            guard let regex = try? Regex(pattern).ignoresCase() else { return nil }
            return Entry(regex: regex, replacement: value)
        }
    }
}
