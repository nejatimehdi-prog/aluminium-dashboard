import Foundation

/// Persian digit, number, money and Jalali date formatting. Pure and deterministic.
enum PersianFormat {
    static let groupSeparator = "٬"
    static let decimalSeparator = "٫"
    static let minusSign = "\u{2212}"

    static let weekdayNames = ["شنبه", "یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه"]

    /// Converts ASCII digits to Persian digits.
    static func digits(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if let v = ch.asciiValue, v >= 48, v <= 57 {
                out.unicodeScalars.append(UnicodeScalar(0x06F0 + UInt32(v - 48))!)
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Groups the magnitude of `value` in threes and converts to Persian digits.
    static func number(_ value: Int64, grouping: Bool = true) -> String {
        let negative = value < 0
        let magnitude = value.magnitude
        let raw = String(magnitude)
        var grouped = raw
        if grouping, raw.count > 3 {
            var parts: [String] = []
            var chars = Array(raw)
            while chars.count > 3 {
                parts.insert(String(chars.suffix(3)), at: 0)
                chars.removeLast(3)
            }
            parts.insert(String(chars), at: 0)
            grouped = parts.joined(separator: groupSeparator)
        }
        return (negative ? minusSign : "") + digits(grouped)
    }

    static func number(_ value: Int, grouping: Bool = true) -> String {
        number(Int64(value), grouping: grouping)
    }

    /// e.g. "۱۲٬۵۰۰٬۰۰۰ تومان". Toman amounts that are not whole show the rial remainder as a decimal.
    static func money(_ money: Money, unit: CurrencyUnit, showUnit: Bool = true, signed: Bool = false) -> String {
        let per = unit.rialsPerUnit
        let whole = money.rials / per
        let remainder = (money.rials % per).magnitude
        var text: String
        if money.rials < 0 && whole == 0 {
            text = minusSign + number(Int64(0))
        } else {
            text = number(whole)
        }
        if remainder != 0 {
            text += decimalSeparator + digits(String(remainder))
        }
        if signed && money.rials > 0 {
            text = "+" + text
        }
        return showUnit ? "\(text) \(unit.title)" : text
    }

    /// Short form for charts and tight spaces: "۱۲٫۵ میلیون".
    static func compactMoney(_ money: Money, unit: CurrencyUnit) -> String {
        let value = Double(money.rials) / Double(unit.rialsPerUnit)
        let magnitude = Swift.abs(value)
        let sign = value < 0 ? minusSign : ""
        var scaled = magnitude
        var suffix = ""
        if magnitude >= 1_000_000_000 {
            scaled = magnitude / 1_000_000_000
            suffix = " میلیارد"
        } else if magnitude >= 1_000_000 {
            scaled = magnitude / 1_000_000
            suffix = " میلیون"
        } else if magnitude >= 1_000 {
            scaled = magnitude / 1_000
            suffix = " هزار"
        }
        let rounded = (scaled * 10).rounded() / 10
        var text: String
        if rounded == rounded.rounded() {
            text = String(Int64(rounded))
        } else {
            text = String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: decimalSeparator)
        }
        text = digits(text)
        return sign + text + suffix
    }

    enum DateStyle {
        /// "۱۶ آبان ۱۴۰۵"
        case long
        /// "۱۴۰۵/۰۸/۱۶"
        case numeric
        /// "جمعه ۱۶ آبان ۱۴۰۵"
        case withWeekday
        /// "۱۶ آبان"
        case dayMonth
    }

    static func date(_ date: CivilDate, style: DateStyle = .long) -> String {
        let j = date.jalali
        let monthName = JalaliCalendar.monthNames[j.month - 1]
        switch style {
        case .long:
            return digits("\(j.day)") + " " + monthName + " " + digits("\(j.year)")
        case .numeric:
            return digits(String(format: "%04d/%02d/%02d", j.year, j.month, j.day))
        case .withWeekday:
            return weekdayNames[date.persianWeekday] + " " + digits("\(j.day)") + " " + monthName + " " + digits("\(j.year)")
        case .dayMonth:
            return digits("\(j.day)") + " " + monthName
        }
    }

    static func monthTitle(_ date: CivilDate) -> String {
        let j = date.jalali
        return JalaliCalendar.monthNames[j.month - 1] + " " + digits("\(j.year)")
    }

    /// "امروز"، "فردا"، "۳ روز دیگر"، "۲ روز پیش"
    static func relativeDays(_ days: Int) -> String {
        switch days {
        case 0: return "امروز"
        case 1: return "فردا"
        case -1: return "دیروز"
        case let d where d > 1: return number(d) + " روز دیگر"
        default: return number(-days) + " روز پیش"
        }
    }
}
