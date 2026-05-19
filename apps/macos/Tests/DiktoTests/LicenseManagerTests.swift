import XCTest
@testable import DiktoLib

final class LicenseManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        #if DEBUG
        LicenseManager.shared._resetForTests()
        #endif
    }

    override func tearDown() {
        #if DEBUG
        LicenseManager.shared._resetForTests()
        #endif
        super.tearDown()
    }

    func testFreeFlavorReportsNotRequired() throws {
        try XCTSkipIf(ProductFlavor.current.requiresLicense, "Pro RU flavor under test")
        XCTAssertEqual(LicenseManager.shared.status, .notRequired)
        XCTAssertTrue(LicenseManager.shared.status.allowsRecording)
    }

    func testTrialJustStartedHasFullDaysLeft() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let now = Date()
        LicenseManager.shared._seedTrial(start: now, lastSeen: now)
        let status = LicenseManager.shared._statusForTesting()
        guard case .trial(let daysLeft) = status else {
            XCTFail("Expected .trial, got \(status)"); return
        }
        XCTAssertEqual(daysLeft, ProductFlavor.current.trialDays)
    }

    func testTrialExpiredAfterTrialDays() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let longAgo = Date().addingTimeInterval(-TimeInterval(ProductFlavor.current.trialDays + 6) * 24 * 3600)
        LicenseManager.shared._seedTrial(start: longAgo, lastSeen: longAgo)
        XCTAssertEqual(LicenseManager.shared._statusForTesting(), .trialExpired)
    }

    func testClockRollbackFreezesTrial() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let start = Date().addingTimeInterval(-3 * 24 * 3600)
        let lastSeenFuture = Date().addingTimeInterval(24 * 3600)
        LicenseManager.shared._seedTrial(start: start, lastSeen: lastSeenFuture)
        let status = LicenseManager.shared._statusForTesting()
        guard case .trial(let daysLeft) = status else {
            XCTFail("Expected .trial, got \(status)"); return
        }
        XCTAssertLessThanOrEqual(daysLeft, ProductFlavor.current.trialDays - 4)
    }

    func testStatusAllowsRecordingDuringTrial() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        LicenseManager.shared._seedTrial(start: Date(), lastSeen: Date())
        XCTAssertTrue(LicenseManager.shared._statusForTesting().allowsRecording)
    }

    func testStatusBlocksRecordingAfterTrial() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let longAgo = Date().addingTimeInterval(-100 * 24 * 3600)
        LicenseManager.shared._seedTrial(start: longAgo, lastSeen: longAgo)
        XCTAssertFalse(LicenseManager.shared._statusForTesting().allowsRecording)
    }

    func testInstallAndClearLicense() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let record = LicenseRecord(
            licenseKey: "ABCD-EFGH-IJKL-MNOP",
            token: "tok_test_123",
            plan: "lifetime",
            expiresAt: Date().addingTimeInterval(365 * 24 * 3600),
            lastValidatedAt: Date()
        )
        try LicenseManager.shared.install(record: record)
        let status = LicenseManager.shared._statusForTesting()
        guard case .active = status else {
            XCTFail("Expected .active, got \(status)"); return
        }
        LicenseManager.shared.clear()
        let after = LicenseManager.shared._statusForTesting()
        if case .active = after { XCTFail("Should not be active after clear") }
    }

    func testExpiredLicenseShowsInvalid() throws {
        try XCTSkipUnless(ProductFlavor.current.requiresLicense, "Free flavor under test")
        let record = LicenseRecord(
            licenseKey: "ABCD-EFGH-IJKL-MNOP",
            token: "tok_test_123",
            plan: "lifetime",
            expiresAt: Date().addingTimeInterval(-3600),
            lastValidatedAt: Date()
        )
        try LicenseManager.shared.install(record: record)
        let status = LicenseManager.shared._statusForTesting()
        if case .invalid = status { /* expected */ } else {
            XCTFail("Expected .invalid for expired license, got \(status)")
        }
    }

    // MARK: - Russian plural helper

    func testTrialDaysLeftRussianPlural() {
        let savedLanguage = L10n.language
        defer { L10n.language = savedLanguage }
        if ProductFlavor.current.forcedLanguage == nil {
            L10n.language = "ru"
        }
        guard L10n.isRussian else { return }
        XCTAssertEqual(L10n.trialDaysLeft(1), "Триал: 1 день")
        XCTAssertEqual(L10n.trialDaysLeft(2), "Триал: 2 дня")
        XCTAssertEqual(L10n.trialDaysLeft(5), "Триал: 5 дней")
        XCTAssertEqual(L10n.trialDaysLeft(11), "Триал: 11 дней")
        XCTAssertEqual(L10n.trialDaysLeft(21), "Триал: 21 день")
        XCTAssertEqual(L10n.trialDaysLeft(22), "Триал: 22 дня")
        XCTAssertEqual(L10n.trialDaysLeft(25), "Триал: 25 дней")
    }
}
