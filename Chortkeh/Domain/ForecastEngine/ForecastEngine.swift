import Foundation

enum ForecastScenario: String, Codable, CaseIterable, Sendable, Identifiable {
    case conservative
    case normal
    case optimistic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conservative: return "محتاطانه"
        case .normal: return "معمولی"
        case .optimistic: return "خوش‌بینانه"
        }
    }

    /// Percentage applied to the daily variable-spending estimate.
    var spendingFactorPercent: Int64 {
        switch self {
        case .conservative: return 120
        case .normal: return 100
        case .optimistic: return 85
        }
    }

    /// Inclusion rule for incoming money (outgoing commitments are always included):
    /// * conservative: only "confirmed" inflows that are not overdue
    /// * normal: confirmed inflows (overdue ones too) + "expected" inflows that are not overdue
    /// * optimistic: every open inflow, including uncertain and overdue ones
    func includesInflow(confidence: ReceiptConfidence, overdue: Bool) -> Bool {
        switch self {
        case .conservative:
            return confidence == .confirmed && !overdue
        case .normal:
            return confidence == .confirmed || (confidence == .expected && !overdue)
        case .optimistic:
            return true
        }
    }

    var explanation: String {
        switch self {
        case .conservative:
            return "فقط دریافتی‌های قطعی و سررسیدنگذشته حساب شده‌اند و هزینه روزمره ۲۰٪ بیشتر برآورد شده است."
        case .normal:
            return "دریافتی‌های قطعی و احتمالی حساب شده‌اند؛ دریافتی‌های نامطمئن کنار گذاشته شده‌اند."
        case .optimistic:
            return "همه دریافتی‌های باز (حتی نامطمئن یا معوق) حساب شده‌اند و هزینه روزمره ۱۵٪ کمتر برآورد شده است."
        }
    }
}

enum ForecastEventKind: String, Codable, Sendable {
    case chequeIssued
    case chequeReceived
    case payable
    case receivable
    case recurringIncome
    case recurringExpense
    case dailySpending
}

struct ForecastEvent: Identifiable, Hashable, Sendable {
    /// Stable forecast owner id (commitment owner, recurrence key, or "spend:<day>").
    let id: String
    let date: CivilDate
    /// Signed: positive = inflow, negative = outflow.
    let amount: Money
    let kind: ForecastEventKind
    let sourceId: UUID?
    let isEstimate: Bool
    /// True when the original due date was in the past and the event was moved to today.
    let wasOverdue: Bool
}

struct ForecastDay: Identifiable, Hashable, Sendable {
    var id: Int { date.dayNumber }
    let date: CivilDate
    let inflow: Money
    let outflow: Money
    let endBalance: Money
}

struct ForecastInput: Sendable {
    var ledger: LedgerSnapshot
    var today: CivilDate
    var horizonDays: Int
    var scenario: ForecastScenario
    var reserve: Money
    /// Whether to subtract an estimated daily variable spending.
    var includeDailySpending: Bool = true
}

struct ForecastResult: Sendable {
    let startBalance: Money
    let today: CivilDate
    let horizonDays: Int
    let scenario: ForecastScenario
    let days: [ForecastDay]
    let events: [ForecastEvent]
    /// First day whose closing balance is below zero.
    let firstShortfall: ForecastDay?
    /// First day whose closing balance is below the user's reserve (if a reserve is set).
    let firstReserveBreach: ForecastDay?
    let minimumDay: ForecastDay?
    let endBalance: Money
    /// Money needed to never go below zero in the window.
    let requiredFunds: Money
    /// Money needed to never go below the reserve.
    let requiredForReserve: Money
    /// Open commitments with no due date: shown separately, never placed on a guessed date.
    let undated: [Commitment]
    let dailySpending: DailySpendingSource
    let assumptions: [String]

    var hasShortfall: Bool { firstShortfall != nil }
}

/// Day-by-day cash-flow projection. Pure; no I/O.
enum ForecastEngine {
    static let supportedHorizons = [7, 15, 30, 60, 90]

    static func run(_ input: ForecastInput) throws -> ForecastResult {
        let ledger = input.ledger
        let today = input.today
        let horizon = max(0, input.horizonDays)
        let end = today.adding(days: horizon)
        let startBalance = try FinancialCalculator.totalCash(ledger)

        var events: [ForecastEvent] = []
        var undated: [Commitment] = []
        var excludedInflows = 0

        // 1–3. Cheques and obligations (each amount owned exactly once).
        for c in try CommitmentResolver.commitments(ledger, today: today) {
            guard let due = c.dueDate else {
                undated.append(c)
                continue
            }
            let overdue = due < today
            let date = overdue ? today : due
            guard date <= end else { continue }
            if c.flow == .inflow {
                guard input.scenario.includesInflow(confidence: c.confidence, overdue: overdue) else {
                    excludedInflows += 1
                    continue
                }
            }
            let signed = try (c.flow == .inflow ? c.amount : c.amount.negated())
            events.append(ForecastEvent(
                id: c.ownerId,
                date: date,
                amount: signed,
                kind: eventKind(c.kind),
                sourceId: c.sourceId,
                isEstimate: false,
                wasOverdue: overdue
            ))
        }

        // 4. Recurring income / expense, minus occurrences already confirmed by a real transaction.
        for occ in try RecurringSchedule.pendingOccurrences(ledger, from: today, through: end) {
            let isIncome = occ.rule.kind == .income
            if isIncome && !input.scenario.includesInflow(confidence: occ.rule.confidence, overdue: false) {
                excludedInflows += 1
                continue
            }
            events.append(ForecastEvent(
                id: "recurring:\(occ.key)",
                date: occ.date,
                amount: try (isIncome ? occ.rule.amount : occ.rule.amount.negated()),
                kind: isIncome ? .recurringIncome : .recurringExpense,
                sourceId: occ.rule.id,
                isEstimate: false,
                wasOverdue: false
            ))
        }

        // 5. Estimated variable spending, starting tomorrow (today's spending is assumed already recorded).
        let source = try SpendingAnalyzer.dailyEstimate(ledger, today: today)
        var daily: Money?
        if input.includeDailySpending {
            switch source {
            case .budget(let m), .historical(let m, _, _):
                daily = try m.scaled(numerator: input.scenario.spendingFactorPercent, denominator: 100)
            case .none:
                daily = nil
            }
        }
        if let daily, daily.isPositive, horizon >= 1 {
            for offset in 1...horizon {
                let d = today.adding(days: offset)
                events.append(ForecastEvent(
                    id: "spend:\(d.dayNumber)",
                    date: d,
                    amount: try daily.negated(),
                    kind: .dailySpending,
                    sourceId: nil,
                    isEstimate: true,
                    wasOverdue: false
                ))
            }
        }

        // 6–7. Roll balances day by day.
        let byDay = Dictionary(grouping: events, by: { $0.date.dayNumber })
        var days: [ForecastDay] = []
        days.reserveCapacity(horizon + 1)
        var balance = startBalance
        for offset in 0...horizon {
            let d = today.adding(days: offset)
            var inflow = Money.zero
            var outflow = Money.zero
            for e in byDay[d.dayNumber] ?? [] {
                if e.amount.isNegative { outflow = try outflow + e.amount.negated() } else { inflow = try inflow + e.amount }
            }
            balance = try balance + inflow - outflow
            days.append(ForecastDay(date: d, inflow: inflow, outflow: outflow, endBalance: balance))
        }

        let firstShortfall = days.first(where: { $0.endBalance.isNegative })
        let reserve = input.reserve
        let firstReserveBreach: ForecastDay? = reserve.isPositive ? days.first(where: { $0.endBalance < reserve }) : nil
        let minimumDay = days.min { $0.endBalance < $1.endBalance }
        let minBalance = minimumDay?.endBalance ?? startBalance
        let required = try (minBalance.isNegative ? minBalance.negated() : Money.zero)
        let gapToReserve = try input.reserve - minBalance
        let requiredForReserve = gapToReserve.isPositive ? gapToReserve : .zero

        var assumptions: [String] = []
        assumptions.append("پیش‌بینی فقط بر اساس اطلاعات ثبت‌شده است و تضمین نیست.")
        assumptions.append(input.scenario.explanation)
        switch source {
        case .budget(let m):
            if input.includeDailySpending {
                assumptions.append("هزینه روزمره از بودجه ماهانه: روزانه حدود \(PersianFormat.money(m, unit: .toman)).")
            }
        case .historical(let m, let covered, let recordDays):
            if input.includeDailySpending {
                assumptions.append("هزینه روزمره از میانگین \(PersianFormat.number(covered)) روز گذشته (\(PersianFormat.number(recordDays)) روز دارای ثبت): روزانه حدود \(PersianFormat.money(m, unit: .toman)).")
            }
        case .none:
            assumptions.append("برای هزینه روزمره داده کافی یا بودجه ثبت نشده؛ این هزینه‌ها در پیش‌بینی نیامده‌اند.")
        }
        if !undated.isEmpty {
            assumptions.append("\(PersianFormat.number(undated.count)) مورد بدون سررسید مشخص، در هیچ تاریخی لحاظ نشده است.")
        }
        if excludedInflows > 0 {
            assumptions.append("\(PersianFormat.number(excludedInflows)) دریافتی به‌دلیل سطح اطمینان در این سناریو حساب نشده است.")
        }
        if events.contains(where: { $0.wasOverdue }) {
            assumptions.append("موارد سررسیدگذشته که هنوز باز هستند، در امروز منظور شده‌اند.")
        }

        return ForecastResult(
            startBalance: startBalance,
            today: today,
            horizonDays: horizon,
            scenario: input.scenario,
            days: days,
            events: events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date },
            firstShortfall: firstShortfall,
            firstReserveBreach: firstReserveBreach,
            minimumDay: minimumDay,
            endBalance: balance,
            requiredFunds: required,
            requiredForReserve: requiredForReserve,
            undated: undated,
            dailySpending: source,
            assumptions: assumptions
        )
    }

    private static func eventKind(_ kind: CommitmentKind) -> ForecastEventKind {
        switch kind {
        case .chequeIssued: return .chequeIssued
        case .chequeReceived: return .chequeReceived
        case .payable: return .payable
        case .receivable: return .receivable
        }
    }
}
