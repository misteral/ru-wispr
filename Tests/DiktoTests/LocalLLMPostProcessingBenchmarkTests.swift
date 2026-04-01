import XCTest
@testable import DiktoLib

final class LocalLLMPostProcessingBenchmarkTests: XCTestCase {

    func testParseCustomOptions() throws {
        let options = try LocalLLMPostProcessingBenchmarkOptions.parse([
            "--text", "hello",
            "--runs", "2",
            "--language", "ru",
            "--model-id", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            "--max-tokens", "128",
            "--temperature", "0.2",
            "--timeout-ms", "5000"
        ])

        XCTAssertEqual(options.text, "hello")
        XCTAssertEqual(options.runs, 2)
        XCTAssertEqual(options.language, "ru")
        XCTAssertEqual(options.modelID, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
        XCTAssertEqual(options.maxTokens, 128)
        XCTAssertEqual(options.temperature, 0.2)
        XCTAssertEqual(options.timeoutMs, 5000)
    }

    func testParseRejectsModelIDAndModelPathTogether() {
        XCTAssertThrowsError(
            try LocalLLMPostProcessingBenchmarkOptions.parse([
                "--model-id", "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                "--model-path", "/tmp/model"
            ])
        ) { error in
            XCTAssertEqual(
                error as? LocalLLMPostProcessingBenchmarkOptionsError,
                .mutuallyExclusiveModelSource
            )
        }
    }

    func testBuiltInSuiteContainsRussianCase() throws {
        let options = LocalLLMPostProcessingBenchmarkOptions()
        let cases = try options.benchmarkCases()

        XCTAssertTrue(cases.contains { $0.name == "ru_mixed_terms" })
        XCTAssertTrue(cases.contains { $0.name == "ru_typo_cleanup" })
    }
}
