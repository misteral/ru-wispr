import XCTest
@testable import DiktoLib

final class GigaAMTranscriberLogicTests: XCTestCase {
    private let mib = 1024 * 1024

    func testRecommendedCacheLimitUsesFallbackWhenWorkingSetUnavailable() {
        XCTAssertEqual(
            GigaAMTranscriber.recommendedCacheLimitBytes(maxRecommendedWorkingSetSize: nil),
            256 * mib
        )
    }

    func testRecommendedCacheLimitKeepsFloorForSmallWorkingSet() {
        XCTAssertEqual(
            GigaAMTranscriber.recommendedCacheLimitBytes(maxRecommendedWorkingSetSize: 256 * mib),
            64 * mib
        )
    }

    func testRecommendedCacheLimitUsesOneEighthOfModerateWorkingSet() {
        XCTAssertEqual(
            GigaAMTranscriber.recommendedCacheLimitBytes(maxRecommendedWorkingSetSize: 1024 * mib),
            128 * mib
        )
    }

    func testRecommendedCacheLimitCapsLargeWorkingSet() {
        XCTAssertEqual(
            GigaAMTranscriber.recommendedCacheLimitBytes(maxRecommendedWorkingSetSize: 16 * 1024 * mib),
            256 * mib
        )
    }
}
