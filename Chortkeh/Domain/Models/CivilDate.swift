import Foundation

struct JalaliDate: Hashable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int
}

/// Pure arithmetic Jalali (Solar Hijri) calendar.
/// Algorithm: Borkowski / jalaali-js (break-year table), valid for Jalali years -61 ... 3177.
/// Day numbers are Julian Day Numbers, so they are independent of any time zone.
enum JalaliCalendar {
    static let monthNames = [
        "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
        "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"
    ]

    private static let breaks = [
        -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210,
        1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178
    ]

    struct YearInfo {
        /// Years since the last leap year (0 means `year` itself is leap).
        let leap: Int
        let gregorianYear: Int
        /// The March day (of `gregorianYear`) on which Farvardin 1 falls.
        let march: Int
    }

    static func yearInfo(_ jy: Int) -> YearInfo {
        let gy = jy + 621
        var leapJ = -14
        var jp = breaks[0]
        var jump = 0
        for i in 1..<breaks.count {
            let jm = breaks[i]
            jump = jm - jp
            if jy < jm { break }
            leapJ = leapJ + (jump / 33) * 8 + (jump % 33) / 4
            jp = jm
        }
        var n = jy - jp
        leapJ = leapJ + (n / 33) * 8 + ((n % 33) + 3) / 4
        if jump % 33 == 4 && jump - n == 4 {
            leapJ += 1
        }
        let leapG = gy / 4 - ((gy / 100 + 1) * 3) / 4 - 150
        let march = 20 + leapJ - leapG
        if jump - n < 6 {
            n = n - jump + ((jump + 4) / 33) * 33
        }
        var leap = (((n + 1) % 33) - 1) % 4
        if leap == -1 { leap = 4 }
        return YearInfo(leap: leap, gregorianYear: gy, march: march)
    }

    static func isLeapYear(_ jy: Int) -> Bool {
        yearInfo(jy).leap == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        if month <= 6 { return 31 }
        if month <= 11 { return 30 }
        return isLeapYear(year) ? 30 : 29
    }

    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard year > -61, year < 3177, (1...12).contains(month), day >= 1 else { return false }
        return day <= daysInMonth(year: year, month: month)
    }

    static func dayNumber(year jy: Int, month jm: Int, day jd: Int) -> Int {
        let info = yearInfo(jy)
        return gregorianDayNumber(year: info.gregorianYear, month: 3, day: info.march)
            + (jm - 1) * 31 - (jm / 7) * (jm - 7) + jd - 1
    }

    static func jalali(dayNumber jdn: Int) -> JalaliDate {
        let gy = gregorian(dayNumber: jdn).year
        var jy = gy - 621
        let info = yearInfo(jy)
        let firstDay = gregorianDayNumber(year: gy, month: 3, day: info.march)
        var k = jdn - firstDay
        if k >= 0 {
            if k <= 185 {
                return JalaliDate(year: jy, month: 1 + k / 31, day: k % 31 + 1)
            }
            k -= 186
        } else {
            jy -= 1
            k += 179
            if info.leap == 1 { k += 1 }
        }
        return JalaliDate(year: jy, month: 7 + k / 30, day: k % 30 + 1)
    }

    static func gregorianDayNumber(year gy: Int, month gm: Int, day gd: Int) -> Int {
        var d = ((gy + (gm - 8) / 6 + 100100) * 1461) / 4
            + (153 * ((gm + 9) % 12) + 2) / 5
            + gd - 34840408
        d = d - (((gy + 100100 + (gm - 8) / 6) / 100) * 3) / 4 + 752
        return d
    }

    static func gregorian(dayNumber jdn: Int) -> (year: Int, month: Int, day: Int) {
        var j = 4 * jdn + 139361631
        j = j + (((4 * jdn + 183187720) / 146097) * 3) / 4 * 4 - 3908
        let i = ((j % 1461) / 4) * 5 + 308
        let gd = (i % 153) / 5 + 1
        let gm = ((i / 153) % 12) + 1
        let gy = j / 1461 - 100100 + (8 - gm) / 6
        return (gy, gm, gd)
    }
}

/// Policy for monthly recurrences anchored on a day that a shorter month does not have (29, 30, 31).
enum MonthEndPolicy: String, Codable, CaseIterable, Sendable {
    /// Use the last valid day of the shorter month (default).
    case lastValidDay
    /// Move to the first day of the following month.
    case firstDayOfNextMonth

    var title: String {
        switch self {
        case .lastValidDay: return "آخرین روز همان ماه"
        case .firstDayOfNextMonth: return "روز اول ماه بعد"
        }
    }
}

/// A calendar day without time or time zone ("due on 15 Dey 1405").
/// Stored as a Julian Day Number so its meaning never shifts with time zone or DST changes.
struct CivilDate: Hashable, Comparable, Codable, Sendable, Identifiable {
    let dayNumber: Int

    var id: Int { dayNumber }

    init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    init(year: Int, month: Int, day: Int) {
        self.dayNumber = JalaliCalendar.gregorianDayNumber(year: year, month: month, day: day)
    }

    init?(jalaliYear: Int, month: Int, day: Int) {
        guard JalaliCalendar.isValid(year: jalaliYear, month: month, day: day) else { return nil }
        self.dayNumber = JalaliCalendar.dayNumber(year: jalaliYear, month: month, day: day)
    }

    var jalali: JalaliDate { JalaliCalendar.jalali(dayNumber: dayNumber) }

    var gregorian: (year: Int, month: Int, day: Int) { JalaliCalendar.gregorian(dayNumber: dayNumber) }

    func adding(days: Int) -> CivilDate {
        CivilDate(dayNumber: dayNumber + days)
    }

    /// Number of days from `self` to `other` (positive if `other` is later).
    func days(until other: CivilDate) -> Int {
        other.dayNumber - dayNumber
    }

    /// Persian weekday: 0 = شنبه … 6 = جمعه.
    var persianWeekday: Int {
        ((dayNumber + 2) % 7 + 7) % 7
    }

    /// First day of the same Jalali month.
    var startOfJalaliMonth: CivilDate {
        let j = jalali
        return CivilDate(dayNumber: JalaliCalendar.dayNumber(year: j.year, month: j.month, day: 1))
    }

    /// Adds Jalali months keeping `anchorDay` when possible and applying `policy` otherwise.
    func addingJalaliMonths(_ months: Int, anchorDay: Int, policy: MonthEndPolicy) -> CivilDate {
        let j = jalali
        let total = (j.year * 12 + (j.month - 1)) + months
        let year = Int((Double(total) / 12).rounded(.down))
        let month = total - year * 12 + 1
        return CivilDate.resolving(year: year, month: month, day: anchorDay, policy: policy)
    }

    static func resolving(year: Int, month: Int, day: Int, policy: MonthEndPolicy) -> CivilDate {
        let maxDay = JalaliCalendar.daysInMonth(year: year, month: month)
        if day <= maxDay {
            return CivilDate(dayNumber: JalaliCalendar.dayNumber(year: year, month: month, day: day))
        }
        switch policy {
        case .lastValidDay:
            return CivilDate(dayNumber: JalaliCalendar.dayNumber(year: year, month: month, day: maxDay))
        case .firstDayOfNextMonth:
            let nextMonth = month == 12 ? 1 : month + 1
            let nextYear = month == 12 ? year + 1 : year
            return CivilDate(dayNumber: JalaliCalendar.dayNumber(year: nextYear, month: nextMonth, day: 1))
        }
    }

    // MARK: - Bridging to Foundation

    static func from(_ date: Date, timeZone: TimeZone = .current) -> CivilDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// The instant at `hour:minute` of this day in `timeZone`.
    func date(hour: Int = 0, minute: Int = 0, timeZone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let g = gregorian
        let comps = DateComponents(year: g.year, month: g.month, day: g.day, hour: hour, minute: minute)
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// Floating (time-zone-less) components, suitable for calendar notification triggers:
    /// the reminder keeps firing on the same local calendar day if the user travels.
    func dateComponents(hour: Int, minute: Int) -> DateComponents {
        let g = gregorian
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = g.year
        comps.month = g.month
        comps.day = g.day
        comps.hour = hour
        comps.minute = minute
        return comps
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        dayNumber = try c.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(dayNumber)
    }
}
