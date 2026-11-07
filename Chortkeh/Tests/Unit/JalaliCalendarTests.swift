import XCTest
@testable import Chortkeh

/// Scenarios 11, 12, 13: short months, Esfand / leap years, time zones.
final class JalaliCalendarTests: XCTestCase {
    func testKnownAnchors() {
        XCTAssertEqual(CivilDate(jalaliYear: 1405, month: 1, day: 1), CivilDate(year: 2026, month: 3, day: 21))
        XCTAssertEqual(CivilDate(jalaliYear: 1405, month: 8, day: 16), CivilDate(year: 2026, month: 11, day: 7))
        XCTAssertEqual(CivilDate(jalaliYear: 1403, month: 12, day: 30), CivilDate(year: 2025, month: 3, day: 20))
        XCTAssertEqual(CivilDate(jalaliYear: 1404, month: 12, day: 29), CivilDate(year: 2026, month: 3, day: 20))
        XCTAssertEqual(CivilDate(year: 2026, month: 11, day: 7).persianWeekday, 0) // Saturday = شنبه
    }

    func testLeapYears() {
        for y in [1395, 1399, 1403, 1408, 1412] { XCTAssertTrue(JalaliCalendar.isLeapYear(y), "\(y)") }
        for y in [1400, 1401, 1402, 1404, 1405, 1406, 1407] { XCTAssertFalse(JalaliCalendar.isLeapYear(y), "\(y)") }
        XCTAssertNil(CivilDate(jalaliYear: 1404, month: 12, day: 30))
        XCTAssertNotNil(CivilDate(jalaliYear: 1403, month: 12, day: 30))
        XCTAssertNil(CivilDate(jalaliYear: 1405, month: 7, day: 31))
    }

    func testRoundTripAndAgreementWithFoundation() {
        var persian = Calendar(identifier: .persian)
        persian.timeZone = TimeZone(identifier: "UTC")!
        let start = CivilDate(year: 2016, month: 1, day: 1)
        for offset in stride(from: 0, to: 365 * 20, by: 1) {
            let d = start.adding(days: offset)
            let j = d.jalali
            XCTAssertEqual(CivilDate(jalaliYear: j.year, month: j.month, day: j.day), d)
            let comps = persian.dateComponents([.year, .month, .day], from: d.date(hour: 12, timeZone: TimeZone(identifier: "UTC")!))
            if comps.year != j.year || comps.month != j.month || comps.day != j.day {
                XCTFail("Mismatch for \(d.gregorian): ours \(j), Foundation \(comps)")
                return
            }
        }
    }

    func testCrossingEsfandAndNewYear() {
        let lastDay1404 = CivilDate(jalaliYear: 1404, month: 12, day: 29)!
        XCTAssertEqual(lastDay1404.adding(days: 1).jalali, JalaliDate(year: 1405, month: 1, day: 1))
        let lastDay1403 = CivilDate(jalaliYear: 1403, month: 12, day: 30)!
        XCTAssertEqual(lastDay1403.adding(days: 1).jalali, JalaliDate(year: 1404, month: 1, day: 1))
    }

    func testDay31InShortMonthPolicies() {
        let start = CivilDate(jalaliYear: 1405, month: 6, day: 31)! // Shahrivar 31
        let mehrLast = start.addingJalaliMonths(1, anchorDay: 31, policy: .lastValidDay)
        XCTAssertEqual(mehrLast.jalali, JalaliDate(year: 1405, month: 7, day: 30))
        let mehrNext = start.addingJalaliMonths(1, anchorDay: 31, policy: .firstDayOfNextMonth)
        XCTAssertEqual(mehrNext.jalali, JalaliDate(year: 1405, month: 8, day: 1))
        // Esfand of a non-leap year has 29 days.
        let esfand = start.addingJalaliMonths(6, anchorDay: 31, policy: .lastValidDay)
        XCTAssertEqual(esfand.jalali, JalaliDate(year: 1405, month: 12, day: 29))
        // Back to a 31-day month keeps the anchor.
        let farvardin = start.addingJalaliMonths(7, anchorDay: 31, policy: .lastValidDay)
        XCTAssertEqual(farvardin.jalali, JalaliDate(year: 1406, month: 1, day: 31))
    }

    func testTimeZoneKeepsCalendarMeaning() {
        let due = CivilDate(jalaliYear: 1405, month: 10, day: 15)!
        let tehran = TimeZone(identifier: "Asia/Tehran")!
        let la = TimeZone(identifier: "America/Los_Angeles")!
        // 23:30 local time on the due day maps back to the same civil day in each zone.
        XCTAssertEqual(CivilDate.from(due.date(hour: 23, minute: 30, timeZone: tehran), timeZone: tehran), due)
        XCTAssertEqual(CivilDate.from(due.date(hour: 0, minute: 5, timeZone: la), timeZone: la), due)
        // Floating notification components carry no time zone: the reminder stays on 15 Dey wherever the user is.
        let comps = due.dateComponents(hour: 9, minute: 0)
        XCTAssertNil(comps.timeZone)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 5)
        XCTAssertEqual(comps.hour, 9)
    }

    func testDeyFifteenth1405IsJanuaryFifth2027() {
        let due = CivilDate(jalaliYear: 1405, month: 10, day: 15)!
        XCTAssertEqual(due.gregorian.year, 2027)
        XCTAssertEqual(due.gregorian.month, 1)
        XCTAssertEqual(due.gregorian.day, 5)
    }

    func testFormatting() {
        let d = CivilDate(jalaliYear: 1405, month: 8, day: 16)!
        XCTAssertEqual(PersianFormat.date(d), "۱۶ آبان ۱۴۰۵")
        XCTAssertEqual(PersianFormat.date(d, style: .numeric), "۱۴۰۵/۰۸/۱۶")
        XCTAssertEqual(PersianFormat.date(d, style: .withWeekday), "شنبه ۱۶ آبان ۱۴۰۵")
        XCTAssertEqual(PersianFormat.relativeDays(3), "۳ روز دیگر")
    }
}
