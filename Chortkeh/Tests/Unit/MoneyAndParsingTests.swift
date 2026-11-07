import XCTest
@testable import Chortkeh

final class MoneyTests: XCTestCase {
    func testTomanConvertsToRialsExactly() throws {
        XCTAssertEqual(try Money.toman(1_250_000).rials, 12_500_000)
        XCTAssertEqual(try Money.from(7, unit: .rial).rials, 7)
    }

    func testOverflowIsDetectedNotWrapped() {
        let big = Money(rials: Int64.max - 5)
        XCTAssertThrowsError(try big + Money(rials: 10)) { XCTAssertEqual($0 as? DomainError, .overflow) }
        XCTAssertThrowsError(try Money(rials: Int64.min) - Money(rials: 1))
        XCTAssertThrowsError(try Money.toman(Int64.max / 5))
        XCTAssertThrowsError(try Money(rials: Int64.min).negated())
    }

    func testSumAndScaling() throws {
        let total = try Money.sum([Money(rials: 10), Money(rials: 25), Money(rials: -5)])
        XCTAssertEqual(total.rials, 30)
        XCTAssertEqual(try Money(rials: 1000).scaled(numerator: 120, denominator: 100).rials, 1200)
    }

    func testFormattingPersianDigitsAndGrouping() throws {
        XCTAssertEqual(PersianFormat.money(try Money.toman(12_500_000), unit: .toman), "۱۲٬۵۰۰٬۰۰۰ تومان")
        XCTAssertEqual(PersianFormat.money(Money(rials: 125), unit: .toman, showUnit: false), "۱۲٫۵")
        XCTAssertEqual(PersianFormat.money(try Money.toman(-3_000), unit: .toman, showUnit: false), "\u{2212}۳٬۰۰۰")
        XCTAssertEqual(PersianFormat.number(Int64(999)), "۹۹۹")
        XCTAssertEqual(PersianFormat.number(Int64(1_000)), "۱٬۰۰۰")
        XCTAssertEqual(PersianFormat.compactMoney(try Money.toman(12_500_000), unit: .toman), "۱۲٫۵ میلیون")
    }
}

/// Scenario 19: big numbers, separators and Persian / Arabic / Latin digits without rounding.
final class AmountInputParserTests: XCTestCase {
    func testDigitsInAllScripts() throws {
        XCTAssertEqual(try AmountInputParser.parseInteger("۱۲۳۴۵۶۷"), 1_234_567)
        XCTAssertEqual(try AmountInputParser.parseInteger("١٢٣٤٥٦٧"), 1_234_567)
        XCTAssertEqual(try AmountInputParser.parseInteger("1234567"), 1_234_567)
        XCTAssertEqual(try AmountInputParser.parseInteger("۱۲۳4٥6۷"), 1_234_567)
    }

    func testSeparators() throws {
        XCTAssertEqual(try AmountInputParser.parseInteger("۱٬۲۵۰٬۰۰۰"), 1_250_000)
        XCTAssertEqual(try AmountInputParser.parseInteger("1,250,000"), 1_250_000)
        XCTAssertEqual(try AmountInputParser.parseInteger("1 250 000"), 1_250_000)
        XCTAssertEqual(try AmountInputParser.parseInteger("1.250.000"), 1_250_000)
        XCTAssertEqual(try AmountInputParser.parseInteger("۱،۲۵۰،۰۰۰"), 1_250_000)
    }

    func testRejectsDecimalsAndGarbage() {
        XCTAssertThrowsError(try AmountInputParser.parseInteger("12.5"))
        XCTAssertThrowsError(try AmountInputParser.parseInteger("12a"))
        XCTAssertThrowsError(try AmountInputParser.parseInteger(""))
        XCTAssertThrowsError(try AmountInputParser.parseInteger("-500"))
    }

    func testLargeAmountsExactAndBounded() throws {
        // 900 trillion toman → exact rials, no floating point.
        let m = try AmountInputParser.parse("۹۰۰٬۰۰۰٬۰۰۰٬۰۰۰٬۰۰۰", unit: .toman)
        XCTAssertEqual(m.rials, 9_000_000_000_000_000)
        XCTAssertThrowsError(try AmountInputParser.parse("99999999999999999999", unit: .toman))
        XCTAssertThrowsError(try AmountInputParser.parse("2000000000000000", unit: .toman)) // > 10^16 rials
    }

    func testZeroIsNotAPositiveAmount() {
        XCTAssertThrowsError(try AmountInputParser.parsePositive("۰", unit: .toman)) {
            XCTAssertEqual($0 as? DomainError, .amountMustBePositive)
        }
    }

    func testLiveFormatting() {
        XCTAssertEqual(AmountInputParser.formatForEditing("1250000"), "۱٬۲۵۰٬۰۰۰")
        XCTAssertEqual(AmountInputParser.formatForEditing("۱۲۵۰a۰۰۰"), "۱٬۲۵۰٬۰۰۰")
        XCTAssertEqual(AmountInputParser.formatForEditing(""), "")
    }
}

final class SmartTextParserTests: XCTestCase {
    let today = CivilDate(jalaliYear: 1405, month: 8, day: 16)!
    let mellat = AccountSnapshot(id: UUID(), name: "ملت", kind: .bank, openingBalance: .zero, isActive: true, sortOrder: 0)

    var context: SmartTextParser.Context {
        .init(today: today, unit: .toman, accounts: [mellat], categories: [])
    }

    func testExpenseSentence() throws {
        let p = SmartTextParser.parse("امروز ۸۵۰ هزار تومان خرید خانه از حساب ملت", context: context)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, try Money.toman(850_000))
        XCTAssertEqual(p.date, today)
        XCTAssertEqual(p.accountId, mellat.id)
        XCTAssertNil(p.contactName)
    }

    func testReceivableSentence() throws {
        let p = SmartTextParser.parse("از رضایی ۲۰ میلیون طلب دارم و موعدش ۲۰ آذر است", context: context)
        XCTAssertEqual(p.kind, .receivable)
        XCTAssertEqual(p.amount, try Money.toman(20_000_000))
        XCTAssertEqual(p.contactName, "رضایی")
        XCTAssertEqual(p.date, CivilDate(jalaliYear: 1405, month: 9, day: 20))
    }

    func testIssuedChequeSentence() throws {
        let p = SmartTextParser.parse("چک ۷۵ میلیون به احمدی برای ۱۵ دی داده‌ام", context: context)
        XCTAssertEqual(p.kind, .chequeIssued)
        XCTAssertEqual(p.amount, try Money.toman(75_000_000))
        XCTAssertEqual(p.contactName, "احمدی")
        XCTAssertEqual(p.date, CivilDate(jalaliYear: 1405, month: 10, day: 15))
    }

    func testChequeCollectedSentenceGoesToSettlementPicker() {
        let p = SmartTextParser.parse("چک رضایی وصول شد", context: context)
        XCTAssertEqual(p.kind, .settle)
        XCTAssertNil(p.amount)
    }

    func testNumberWords() throws {
        XCTAssertEqual(PersianNumberWords.value(of: ["یک", "میلیون", "و", "دویست", "هزار"]), 1_200_000)
        XCTAssertEqual(PersianNumberWords.value(of: ["۱.۵", "میلیارد"]), 1_500_000_000)
        let p = SmartTextParser.parse("امروز یک میلیون و دویست هزار تومان بنزین و تعمیر ماشین دادم", context: context)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, try Money.toman(1_200_000))
    }

    func testAmbiguousAmountIsNotGuessed() {
        let p = SmartTextParser.parse("۲ میلیون یا ۳ میلیون خرج کردم", context: context)
        XCTAssertNil(p.amount)
    }
}
