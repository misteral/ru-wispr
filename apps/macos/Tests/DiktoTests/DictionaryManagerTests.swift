import XCTest
@testable import DiktoLib

final class DictionaryManagerTests: XCTestCase {

    private func make(_ dict: [String: String]) -> DictionaryManager {
        DictionaryManager(dictionary: dict)
    }

    func testReplacesSingleRussianWord() {
        let manager = make(["свифт": "Swift"])
        XCTAssertEqual(manager.apply(to: "пишу на свифт"), "пишу на Swift")
    }

    func testReplacesMultiWordPhrase() {
        let manager = make(["икс код": "Xcode"])
        XCTAssertEqual(manager.apply(to: "открыл икс код вчера"), "открыл Xcode вчера")
    }

    func testCaseInsensitive() {
        let manager = make(["свифт": "Swift"])
        XCTAssertEqual(manager.apply(to: "учу Свифт"), "учу Swift")
        XCTAssertEqual(manager.apply(to: "учу СВИФТ"), "учу Swift")
    }

    func testWordBoundaryDoesNotMatchSubstring() {
        let manager = make(["рект": "React"])
        // "ректор" contains "рект" but should NOT match.
        XCTAssertEqual(manager.apply(to: "ректор института"), "ректор института")
    }

    func testWordBoundaryAtSentenceStartAndEnd() {
        let manager = make(["свифт": "Swift"])
        XCTAssertEqual(manager.apply(to: "свифт"), "Swift")
        XCTAssertEqual(manager.apply(to: "свифт."), "Swift.")
        XCTAssertEqual(manager.apply(to: "люблю свифт"), "люблю Swift")
    }

    func testMultipleReplacementsInOneString() {
        let manager = make([
            "свифт": "Swift",
            "икс код": "Xcode",
        ])
        XCTAssertEqual(
            manager.apply(to: "пишу на свифт в икс код"),
            "пишу на Swift в Xcode"
        )
    }

    func testLongerPhraseWinsOverShorterPrefix() {
        let manager = make([
            "джава": "Java",
            "джава скрипт": "JavaScript",
        ])
        XCTAssertEqual(manager.apply(to: "учу джава скрипт"), "учу JavaScript")
        XCTAssertEqual(manager.apply(to: "учу джава"), "учу Java")
    }

    func testPlainTextPassesThrough() {
        let manager = make(["свифт": "Swift"])
        XCTAssertEqual(manager.apply(to: "обычный текст"), "обычный текст")
    }

    func testEmptyDictionaryNoOp() {
        let manager = make([:])
        XCTAssertEqual(manager.apply(to: "ничего не меняется"), "ничего не меняется")
    }

    func testEmptyString() {
        let manager = make(["свифт": "Swift"])
        XCTAssertEqual(manager.apply(to: ""), "")
    }

    func testDefaultDictionaryCoversTaskExamples() {
        let manager = DictionaryManager(dictionary: DictionaryManager.defaultDictionary)
        XCTAssertEqual(manager.apply(to: "икс код"), "Xcode")
        XCTAssertEqual(manager.apply(to: "визо студио"), "Visual Studio")
        XCTAssertEqual(manager.apply(to: "рубин релс"), "Ruby on Rails")
        XCTAssertEqual(manager.apply(to: "питон"), "Python")
        XCTAssertEqual(manager.apply(to: "докер и кубернетес"), "Docker и Kubernetes")
        XCTAssertEqual(manager.apply(to: "гетхаб"), "GitHub")
        XCTAssertEqual(manager.apply(to: "гитхаб"), "GitHub")
    }

    // MARK: - Disk persistence

    func testLoadsFromExistingFile() throws {
        let url = makeTempDictionaryFile([
            "тест": "Test",
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = DictionaryManager(file: url)
        XCTAssertEqual(manager.apply(to: "запускаю тест"), "запускаю Test")
    }

    func testCreatesDefaultFileWhenMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiktoDictTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("dictionary.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let manager = DictionaryManager(file: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Default mappings should be in effect.
        XCTAssertEqual(manager.apply(to: "икс код"), "Xcode")

        // The written file should round-trip back to the default dictionary.
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(decoded, DictionaryManager.defaultDictionary)
    }

    func testFallsBackToDefaultsOnCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiktoDictTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("dictionary.json")
        try "{ this is not valid json".write(to: url, atomically: true, encoding: .utf8)

        let manager = DictionaryManager(file: url)
        XCTAssertEqual(manager.apply(to: "икс код"), "Xcode")
    }

    /// The shipped `Resources/dictionary.json` must stay in sync with the
    /// hardcoded `defaultDictionary` constant — they are both used as defaults
    /// (bundle in production, hardcoded in tests / `swift run`). If they drift,
    /// users see different defaults depending on how they launched the app.
    func testBundledJSONMatchesHardcodedDefaults() throws {
        let resourcesDir = URL(filePath: #filePath)
            .deletingLastPathComponent()  // Tests/DiktoTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appending(path: "Resources/dictionary.json")

        let data = try Data(contentsOf: resourcesDir)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(decoded, DictionaryManager.defaultDictionary,
                       "Resources/dictionary.json drifted from DictionaryManager.defaultDictionary — update both")
    }

    private func makeTempDictionaryFile(_ dict: [String: String]) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiktoDictTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("dictionary.json")
        let data = try! JSONEncoder().encode(dict)
        try! data.write(to: url)
        return url
    }
}
