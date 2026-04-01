import XCTest
@testable import DiktoLib

final class FoundationModelBenchmarkSupportTests: XCTestCase {

    func testParseTextOption() throws {
        let options = try FoundationModelBenchmarkOptions.parse([
            "--text", "hello world",
            "--runs", "3",
            "--locale", "en-US",
            "--max-tokens", "64",
            "--no-prewarm"
        ])

        XCTAssertEqual(options.text, "hello world")
        XCTAssertNil(options.filePath)
        XCTAssertEqual(options.runs, 3)
        XCTAssertEqual(options.localeIdentifier, "en-US")
        XCTAssertEqual(options.maxResponseTokens, 64)
        XCTAssertFalse(options.prewarm)
    }

    func testParseRejectsBothTextAndFile() {
        XCTAssertThrowsError(
            try FoundationModelBenchmarkOptions.parse([
                "--text", "hello",
                "--file", "/tmp/input.txt"
            ])
        ) { error in
            XCTAssertEqual(error as? FoundationModelBenchmarkOptionsError, .mutuallyExclusiveInputs)
        }
    }

    func testBenchmarkCasesReturnsBuiltInSuiteByDefault() throws {
        let options = FoundationModelBenchmarkOptions()
        let cases = try options.benchmarkCases()

        XCTAssertEqual(cases, FoundationModelBenchmarkCase.builtInSuite)
        XCTAssertFalse(cases.isEmpty)
    }

    func testNormalizedCollapsesWhitespace() {
        XCTAssertEqual(
            FoundationModelBenchmarkQuality.normalized("  Hello   world\n\nfrom   Dikto  "),
            "Hello world from Dikto"
        )
    }

    func testExactMatchIgnoresWhitespaceOnly() {
        XCTAssertTrue(
            FoundationModelBenchmarkQuality.exactMatch(
                expected: "Hello world",
                actual: " Hello   world\n"
            )
        )
    }

    func testSimilarityForMinorEditIsHigh() {
        let similarity = FoundationModelBenchmarkQuality.similarity(
            expected: "SwiftUI and Xcode",
            actual: "Swift UI and Xcode"
        )

        XCTAssertGreaterThan(similarity, 0.8)
        XCTAssertLessThan(similarity, 1.0)
    }
}
