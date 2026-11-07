import Foundation

/// Historical variable-spending statistics. Days without records are reported as "no data",
/// never as "zero spending".
struct SpendingStats: Equatable, Sendable {
    /// Average variable spending per calendar day over the last 7 days, if there is at least 7 days of history.
    var average7: Money?
    /// Average over the last 30 days (or since the first record, minimum 7 days of history).
    var average30: Money?
    var daysWithRecords7: Int
    var daysWithRecords30: Int
    /// Calendar days covered by the 30-day average (≤ 30).
    var coveredDays30: Int
    var lastExpenseDate: CivilDate?
    /// Whole days since the last recorded expense (nil if none ever).
    var daysSinceLastExpense: Int?
    var firstExpenseDate: CivilDate?
}

enum DailySpendingSource: Equatable, Sendable {
    case budget(Money)
    case historical(Money, coveredDays: Int, daysWithRecords: Int)
    case none
}

enum SpendingAnalyzer {
    static let minimumHistoryDays = 7

    /// Variable expenses only: real expenses that are not reversed and not tied to a recurring rule.
    static func variableExpenses(_ ledger: LedgerSnapshot) -> [TransactionSnapshot] {
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        return ledger.transactions.filter { $0.kind == .expense && $0.recurrenceKey == nil && !reversed.contains($0.id) }
    }

    /// Any recorded expense (including recurring) — used for "you have not recorded anything" nudges.
    static func lastRecordedExpense(_ ledger: LedgerSnapshot, today: CivilDate) -> CivilDate? {
        ledger.transactions.filter { $0.kind == .expense && $0.date <= today }.map(\.date).max()
    }

    static func stats(_ ledger: LedgerSnapshot, today: CivilDate) throws -> SpendingStats {
        let expenses = variableExpenses(ledger).filter { $0.date <= today }
        let first = expenses.map(\.date).min()
        let last = lastRecordedExpense(ledger, today: today)

        func window(_ days: Int) throws -> (avg: Money?, recordDays: Int, covered: Int) {
            let start = today.adding(days: -(days - 1))
            let inWindow = expenses.filter { $0.date >= start }
            let recordDays = Set(inWindow.map(\.date)).count
            guard let first else { return (nil, 0, 0) }
            let effectiveStart = Swift.max(start, first)
            let covered = effectiveStart.days(until: today) + 1
            guard covered >= minimumHistoryDays else { return (nil, recordDays, covered) }
            let total = try Money.sum(inWindow.map(\.amount))
            return (Money(rials: total.rials / Int64(covered)), recordDays, covered)
        }

        let w7 = try window(7)
        let w30 = try window(30)
        return SpendingStats(
            average7: w7.avg,
            average30: w30.avg,
            daysWithRecords7: w7.recordDays,
            daysWithRecords30: w30.recordDays,
            coveredDays30: w30.covered,
            lastExpenseDate: last,
            daysSinceLastExpense: last.map { $0.days(until: today) },
            firstExpenseDate: first
        )
    }

    /// Daily variable-spending estimate: the user's monthly budget wins; otherwise the 30-day average.
    static func dailyEstimate(_ ledger: LedgerSnapshot, today: CivilDate) throws -> DailySpendingSource {
        if let budget = ledger.monthlyBudget, budget.isPositive {
            return .budget(Money(rials: budget.rials / 30))
        }
        let s = try stats(ledger, today: today)
        if let avg = s.average30, avg.isPositive {
            return .historical(avg, coveredDays: s.coveredDays30, daysWithRecords: s.daysWithRecords30)
        }
        return .none
    }
}
