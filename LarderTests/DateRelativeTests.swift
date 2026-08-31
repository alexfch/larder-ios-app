import XCTest
@testable import Larder

/// `Date+Relative` centralizes the day-granularity relative-date math and phrasing that used to
/// be reimplemented in five places (see the file's own doc comment). The exact wording — "today"
/// / "in N days" / "N days ago" — is user-facing on the hub rows, Stock list, and item detail,
/// so it is worth locking down.
final class DateRelativeTests: XCTestCase {

    private func daysFromNow(_ days: Int, file: StaticString = #filePath, line: UInt = #line) throws -> Date {
        // Offset from the start of today, then nudge past noon so a fractional day near a
        // DST/midnight boundary can't tip the calendar-day count.
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let shifted = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: days, to: startOfDay), file: file, line: line)
        return shifted.addingTimeInterval(12 * 3600)
    }

    func testDaysFromTodayCountsWholeCalendarDays() throws {
        XCTAssertEqual(try daysFromNow(0).daysFromToday, 0)
        XCTAssertEqual(try daysFromNow(1).daysFromToday, 1)
        XCTAssertEqual(try daysFromNow(14).daysFromToday, 14)
        XCTAssertEqual(try daysFromNow(-3).daysFromToday, -3)
    }

    func testRelativeDayLabelWording() throws {
        XCTAssertEqual(try daysFromNow(0).relativeDayLabel, "today")
        XCTAssertEqual(try daysFromNow(1).relativeDayLabel, "in 1 days")
        XCTAssertEqual(try daysFromNow(7).relativeDayLabel, "in 7 days")
        XCTAssertEqual(try daysFromNow(-1).relativeDayLabel, "1 days ago")
        XCTAssertEqual(try daysFromNow(-5).relativeDayLabel, "5 days ago")
    }

    // MARK: Lot expiry helpers

    func testLotIsExpiringSoonWithinFourteenDaysInclusive() throws {
        let lot = Lot(itemId: "a", qty: 1, exp: try daysFromNow(14))
        XCTAssertTrue(lot.isExpiringSoon)
        XCTAssertEqual(lot.daysUntilExpiry, 14)
    }

    func testLotIsNotExpiringSoonBeyondFourteenDays() throws {
        let lot = Lot(itemId: "a", qty: 1, exp: try daysFromNow(15))
        XCTAssertFalse(lot.isExpiringSoon)
    }

    func testAlreadyExpiredLotCountsAsExpiringSoon() throws {
        let lot = Lot(itemId: "a", qty: 1, exp: try daysFromNow(-2))
        XCTAssertTrue(lot.isExpiringSoon, "a past date is <= 14 and must still surface")
        XCTAssertEqual(lot.daysUntilExpiry, -2)
    }
}
