import XCTest
@testable import DiktoLib

final class LocalLLMEvaluationSupportTests: XCTestCase {

    func testLoadDatasetParsesJSONLAndSkipsComments() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try """
        # comment
        {"id":"one","input":"hello","expected":"Hello.","tags":["en"]}
        {"id":"two","input":"превет","expected":"Привет.","tags":["ru"]}
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let dataset = try LocalLLMEvaluationLoader.loadDataset(from: url)
        XCTAssertEqual(dataset.count, 2)
        XCTAssertEqual(dataset[0].id, "one")
        XCTAssertEqual(dataset[1].expected, "Привет.")
    }

    func testLoadModelsSortsByPriority() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let json = """
        [
          {"id":"b","path":null,"family":"Qwen","sizeLabel":"1.5B","priority":2},
          {"id":"a","path":null,"family":"Qwen","sizeLabel":"0.5B","priority":1}
        ]
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let models = try LocalLLMEvaluationLoader.loadModels(from: url)
        XCTAssertEqual(models.map(\.sourceDescription), ["a", "b"])
    }
}
