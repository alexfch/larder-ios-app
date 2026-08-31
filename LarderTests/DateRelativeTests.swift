import XCTest
@testable import Larder

/// Covers the shared relative-date helpers in `Date+Relative.swift` that drive every expiry
/// label and badge in the app (`ExpiryBadge`, `HubRow`, `ItemDetailView`, `Lot`). Previously
/// only exercised transitively.
final class DateRelativeTests: XCTestCase {

    private func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }

    func testDaysFromTodayIsZeroForAnyTimeToday() {
        XCTAssertEqual(Date.now.daysFromToday, 0)
        // A later moment on the same calendar day is still "0 days" away, not 1.
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
        XCTAssertEqual(endOfToday.daysFromToday, 0)
    }

    func testDaysFromTodayCountsWholeCalendarDaysAhead() {
        XCTAssertEqual(daysFromNow(1).daysFromToday, 1)
        XCTAssertEqual(daysFromNow(14).daysFromToday, 14)
    }

    func testDaysFromTodayIsNegativeForPastDates() {
        XCTAssertEqual(daysFromNow(-3).daysFromToday, -3)
    }

    func testRelativeDayLabelForToday() {
        XCTAssertEqual(Date.now.relativeDayLabel, "today")
    }

    func testRelativeDayLabelForFutureDates() {
        // NOTE: the singular case reads "in 1 days" — grammatically off, but the PRD's FR-5.2
        // examples ("in 3 days", "12 days ago") never pin down the singular form, so this is
        // characterised here as current behaviour rather than asserted as a defect.
        XCTAssertEqual(daysFromNow(1).relativeDayLabel, "in 1 days")
        XCTAssertEqual(daysFromNow(7).relativeDayLabel, "in 7 days")
    }

    func testRelativeDayLabelForPastDates() {
        XCTAssertEqual(daysFromNow(-1).relativeDayLabel, "1 days ago")
        XCTAssertEqual(daysFromNow(-10).relativeDayLabel, "10 days ago")
    }

    func testLotExpiryHelpersTrackTheUnderlyingDate() {
        let lot = Lot(itemId: "x", qty: 1, exp: daysFromNow(5))
        XCTAssertEqual(lot.daysUntilExpiry, 5)
        XCTAssertTrue(lot.isExpiringSoon)

        let farLot = Lot(itemId: "x", qty: 1, exp: daysFromNow(40))
        XCTAssertFalse(farLot.isExpiringSoon)
    }
}
