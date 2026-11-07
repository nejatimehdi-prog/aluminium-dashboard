import Foundation

enum QuickEntryKind: String, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case payable
    case receivable
    case chequeIssued
    case chequeReceived
    case transfer
    case settle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "هزینه کردم"
        case .income: return "درآمد گرفتم"
        case .payable: return "بدهکار شدم"
        case .receivable: return "طلبکار شدم"
        case .chequeIssued: return "چک دادم"
        case .chequeReceived: return "چک گرفتم"
        case .transfer: return "انتقال بین حساب‌ها"
        case .settle: return "تسویه طلب/بدهی یا چک"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "cart"
        case .income: return "arrow.down.circle"
        case .payable: return "person.crop.circle.badge.minus"
        case .receivable: return "person.crop.circle.badge.plus"
        case .chequeIssued: return "doc.text"
        case .chequeReceived: return "doc.text.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .settle: return "checkmark.seal"
        }
    }
}

/// Result of local, rule-based sentence parsing. Every field is a suggestion shown in an editable
/// form; nothing is saved without the user's confirmation. Unclear parts stay nil (no guessing).
struct ParsedEntry: Equatable, Sendable {
    var kind: QuickEntryKind?
    var amount: Money?
    var date: CivilDate?
    var accountId: UUID?
    var contactName: String?
    var categoryId: UUID?
    var note: String
}

/// Converts Persian number words and digit groups to integers: "یک میلیون و دویست هزار" → 1_200_000,
/// "۲۰ میلیون" → 20_000_000, "۱.۵ میلیارد" → 1_500_000_000.
enum PersianNumberWords {
    static let units: [String: Int64] = [
        "صفر": 0, "یک": 1, "يك": 1, "یه": 1, "دو": 2, "سه": 3, "چهار": 4, "پنج": 5, "شش": 6, "شیش": 6,
        "هفت": 7, "هشت": 8, "نه": 9, "ده": 10, "یازده": 11, "دوازده": 12, "سیزده": 13,
        "چهارده": 14, "پانزده": 15, "پونزده": 15, "شانزده": 16, "شونزده": 16, "هفده": 17, "هجده": 18, "هیجده": 18, "نوزده": 19,
        "بیست": 20, "سی": 30, "چهل": 40, "پنجاه": 50, "شصت": 60, "هفتاد": 70, "هشتاد": 80, "نود": 90,
        "صد": 100, "یکصد": 100, "دویست": 200, "سیصد": 300, "چهارصد": 400, "پانصد": 500, "پونصد": 500,
        "ششصد": 600, "هفتصد": 700, "هشتصد": 800, "نهصد": 900
    ]

    static let multipliers: [String: Int64] = [
        "هزار": 1_000, "میلیون": 1_000_000, "ملیون": 1_000_000, "میلیارد": 1_000_000_000, "میلیاد": 1_000_000_000
    ]

    /// Parses a token sequence that forms one number. Returns nil if any token is not a number word/digit.
    static func value(of tokens: [String]) -> Int64? {
        var total: Decimal = 0
        var current: Decimal = 0
        var sawAny = false
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .punctuationCharacters)
            if token == "و" { continue }
            if let m = multipliers[token] {
                total += (current == 0 ? 1 : current) * Decimal(m)
                current = 0
                sawAny = true
            } else if let u = units[token] {
                current += Decimal(u)
                sawAny = true
            } else if let d = numericValue(token) {
                current += d
                sawAny = true
            } else {
                return nil
            }
        }
        guard sawAny else { return nil }
        let result = total + current
        guard result >= 0, result < Decimal(Int64.max / 100) else { return nil }
        var rounded = Decimal()
        var copy = result
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// "۱۲۰۰۰۰۰", "1,200,000", "۱.۵" (decimal only meaningful before a multiplier).
    static func numericValue(_ token: String) -> Decimal? {
        let ascii = AmountInputParser.normalizeDigits(token)
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: "/", with: ".")
            .filter { !",٬،".contains($0) }
        guard !ascii.isEmpty, ascii.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }),
              ascii.filter({ $0 == "." }).count <= 1, ascii.first != "."
        else { return nil }
        return Decimal(string: ascii, locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum SmartTextParser {
    struct Context {
        var today: CivilDate
        var unit: CurrencyUnit
        var accounts: [AccountSnapshot]
        var categories: [CategorySnapshot]
    }

    /// Ordered: the first matching category wins, so results are deterministic.
    private static let categoryKeywords: [(name: String, keywords: [String])] = [
        ("خودرو و سوخت", ["بنزین", "سوخت", "ماشین", "تعمیر", "کارواش"]),
        ("درمان", ["دکتر", "دارو", "داروخانه", "بیمارستان", "دندان"]),
        ("خوراک", ["غذا", "رستوران", "ناهار", "شام", "صبحانه"]),
        ("خانواده و آموزش", ["مدرسه", "شهریه", "کلاس", "کتاب"]),
        ("سفر", ["سفر", "هتل", "بلیت", "بلیط"]),
        ("تفریح", ["سینما", "تفریح", "کافه"]),
        ("خانه", ["اجاره", "شارژ", "قبض", "خانه"]),
        ("خرید روزانه", ["خرید", "سوپر", "میوه", "نان"])
    ]

    static func parse(_ sentence: String, context: Context) -> ParsedEntry {
        let text = DashboardBuilder.normalizeForSearch(sentence)
        let tokens = tokenize(text)
        var entry = ParsedEntry(kind: nil, amount: nil, date: nil, accountId: nil, contactName: nil, categoryId: nil, note: sentence)

        entry.kind = detectKind(text)
        entry.amount = detectAmount(tokens: tokens, unit: context.unit)
        entry.date = detectDate(tokens: tokens, context: context, preferFuture: entry.kind.map(isFutureKind) ?? false)
        entry.accountId = context.accounts.first { account in
            let name = DashboardBuilder.normalizeForSearch(account.name)
            return !name.isEmpty && text.contains(name)
        }?.id
        entry.contactName = detectContact(tokens: tokens, accounts: context.accounts)
        if entry.kind == .expense || entry.kind == nil {
            entry.categoryId = detectCategory(text, categories: context.categories)
        }
        return entry
    }

    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "،" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".!؟?:؛")) }
            .filter { !$0.isEmpty }
    }

    private static func isFutureKind(_ kind: QuickEntryKind) -> Bool {
        switch kind {
        case .payable, .receivable, .chequeIssued, .chequeReceived: return true
        default: return false
        }
    }

    static func detectKind(_ text: String) -> QuickEntryKind? {
        let hasCheque = text.contains("چک")
        if hasCheque {
            if text.contains("وصول") || text.contains("پاس شد") { return .settle }
            if text.contains("دادم") || text.contains("داده‌ام") || text.contains("داده ام") || text.contains("صادر") || text.contains("کشیدم") {
                return .chequeIssued
            }
            if text.contains("گرفتم") || text.contains("گرفته‌ام") || text.contains("گرفته ام") || text.contains("دریافت") {
                return .chequeReceived
            }
        }
        if text.contains("طلب دارم") || text.contains("طلبکار") || text.contains("بهم بدهکار") || text.contains("به من بدهکار") {
            return .receivable
        }
        if text.contains("بدهکارم") || text.contains("بدهکار شدم") || text.contains("بدهی دارم") || text.contains("قرض گرفتم") {
            return .payable
        }
        if text.contains("تسویه") { return .settle }
        if text.contains("انتقال") || text.contains("منتقل") { return .transfer }
        if text.contains("حقوق") || text.contains("درآمد") || text.contains("واریز شد") || text.contains("دریافت کردم") {
            return .income
        }
        if text.contains("خرید") || text.contains("خرج") || text.contains("هزینه") || text.contains("دادم") || text.contains("پرداخت") {
            return .expense
        }
        return nil
    }

    /// Finds exactly one amount. Two different candidate amounts → nil (ask the user instead of guessing).
    static func detectAmount(tokens: [String], unit: CurrencyUnit) -> Money? {
        var candidates: [Money] = []
        var i = 0
        while i < tokens.count {
            // Longest run of number-ish tokens starting at i.
            var j = i
            var run: [String] = []
            while j < tokens.count, isNumberish(tokens[j]) {
                run.append(tokens[j])
                j += 1
            }
            // Trailing "و" is not part of the number.
            while run.last == "و" { run.removeLast() }
            if !run.isEmpty, run != ["و"], let value = PersianNumberWords.value(of: run), value > 0 {
                let unitWord = j < tokens.count ? tokens[j] : ""
                let hasMultiplier = run.contains { PersianNumberWords.multipliers[$0] != nil }
                var effectiveUnit: CurrencyUnit?
                if unitWord.hasPrefix("تومن") || unitWord.hasPrefix("تومان") { effectiveUnit = .toman }
                if unitWord.hasPrefix("ریال") { effectiveUnit = .rial }
                // A bare small number without unit or multiplier (e.g. a day "20") is not an amount.
                if effectiveUnit != nil || hasMultiplier || value >= 1_000 {
                    if !isDayBeforeMonth(tokens: tokens, index: j),
                       let money = try? Money.from(value, unit: effectiveUnit ?? unit),
                       money.rials <= Money.maxInputRials {
                        candidates.append(money)
                    }
                }
            }
            i = max(j, i + 1)
        }
        let unique = Array(Set(candidates))
        return unique.count == 1 ? unique[0] : nil
    }

    private static func isNumberish(_ token: String) -> Bool {
        token == "و" || PersianNumberWords.units[token] != nil || PersianNumberWords.multipliers[token] != nil
            || PersianNumberWords.numericValue(token) != nil
    }

    private static func isDayBeforeMonth(tokens: [String], index: Int) -> Bool {
        guard index < tokens.count else { return false }
        return JalaliCalendar.monthNames.contains(tokens[index])
    }

    static func detectDate(tokens: [String], context: Context, preferFuture: Bool) -> CivilDate? {
        if tokens.contains("امروز") { return context.today }
        if tokens.contains("دیروز") { return context.today.adding(days: -1) }
        if tokens.contains("پریروز") { return context.today.adding(days: -2) }
        if tokens.contains("فردا") { return context.today.adding(days: 1) }
        for (index, token) in tokens.enumerated() {
            guard let month = JalaliCalendar.monthNames.firstIndex(of: token).map({ $0 + 1 }), index > 0 else { continue }
            guard let dayDecimal = PersianNumberWords.numericValue(tokens[index - 1]) ?? PersianNumberWords.units[tokens[index - 1]].map({ Decimal($0) }) else { continue }
            let day = NSDecimalNumber(decimal: dayDecimal).intValue
            var year = context.today.jalali.year
            if index + 1 < tokens.count, let y = PersianNumberWords.numericValue(tokens[index + 1]) {
                let yi = NSDecimalNumber(decimal: y).intValue
                if yi >= 1300 && yi <= 1500 { year = yi }
                else if yi >= 0 && yi <= 99 { year = 1400 + yi }
            } else if let candidate = CivilDate(jalaliYear: year, month: month, day: day) {
                // Without an explicit year, due dates point to the next occurrence; past events to the last.
                if preferFuture && candidate < context.today { year += 1 }
                if !preferFuture && candidate > context.today { year -= 1 }
            }
            return CivilDate(jalaliYear: year, month: month, day: day)
        }
        return nil
    }

    /// "از رضایی ..." / "به احمدی ..." → the single word after the preposition,
    /// unless it is an account name, a number or a generic word.
    static func detectContact(tokens: [String], accounts: [AccountSnapshot]) -> String? {
        let stopWords: Set<String> = ["حساب", "کارت", "بانک", "طرف", "من", "تو", "او", "ما", "امروز", "دیروز", "فردا", "مبلغ", "بابت", "برای"]
        let accountNames = Set(accounts.map { DashboardBuilder.normalizeForSearch($0.name) })
        for (index, token) in tokens.enumerated() where (token == "از" || token == "به") && index + 1 < tokens.count {
            let candidate = tokens[index + 1]
            if stopWords.contains(candidate) || accountNames.contains(candidate) || isNumberish(candidate) { continue }
            if JalaliCalendar.monthNames.contains(candidate) { continue }
            return candidate
        }
        return nil
    }

    static func detectCategory(_ text: String, categories: [CategorySnapshot]) -> UUID? {
        for entry in categoryKeywords where entry.keywords.contains(where: { text.contains($0) }) {
            if let c = categories.first(where: { $0.name == entry.name && !$0.isArchived }) { return c.id }
        }
        return nil
    }
}
