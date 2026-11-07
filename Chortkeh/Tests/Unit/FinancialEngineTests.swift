import XCTest
@testable import Chortkeh

/// Pure tests of the financial core — acceptance scenarios 1–10, 14, 15 (database-free).
final class FinancialEngineTests: XCTestCase {
    typealias B = LedgerBuilder

    // 1. 200M balance, 10M expense → 190M.
    func testExpenseReducesBalance() throws {
        var b = B()
        let acc = b.account(opening: B.m(200))
        b.tx(.expense, B.m(10), from: acc)
        XCTAssertEqual(try FinancialCalculator.balance(of: acc, in: b.ledger), B.m(190))
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(190))
    }

    // 2. Transfer 50M between accounts → total unchanged.
    func testTransferKeepsTotal() throws {
        var b = B()
        let a = b.account("ملت", opening: B.m(120))
        let c = b.account("نقد", opening: B.m(30))
        b.tx(.transfer, B.m(50), from: a, to: c)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(150))
        XCTAssertEqual(try FinancialCalculator.balance(of: a, in: b.ledger), B.m(70))
        XCTAssertEqual(try FinancialCalculator.balance(of: c, in: b.ledger), B.m(80))
        let totals = try FinancialCalculator.periodTotals(b.ledger, from: b.today, through: b.today)
        XCTAssertEqual(totals.expense, .zero)
        XCTAssertEqual(totals.income, .zero)
    }

    // 3. Issuing an 80M cheque does not change cash; it appears as a dated commitment.
    func testIssuedChequeDoesNotChangeCash() throws {
        var b = B()
        b.account(opening: B.m(200))
        let p = b.contact("احمدی")
        b.cheque(.issued, B.m(80), contact: p, dueIn: 10)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(200))
        let due = try DashboardBuilder.dueItems(b.ledger, today: b.today, withinDays: 30)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due[0].amount, B.m(80))
        XCTAssertEqual(due[0].flow, .outflow)
        XCTAssertEqual(try FinancialCalculator.position(b.ledger).payables, B.m(80))
    }

    // 4. Receiving a 40M cheque: no cash change; on collection, cash rises exactly once.
    func testReceivedChequeCollectedOnce() throws {
        var b = B()
        let acc = b.account(opening: B.m(100))
        let p = b.contact("رضایی")
        let ch = b.cheque(.received, B.m(40), contact: p, dueIn: 5)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(100))
        let tx = b.tx(.settlementIn, B.m(40), to: acc, day: 5)
        b.settle(cheque: ch, B.m(40), transaction: tx)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(140))
        XCTAssertEqual(try FinancialCalculator.status(of: b.ledger.cheques[0], settlements: b.ledger.settlements, today: b.today), .settled)
        XCTAssertTrue(try CommitmentResolver.commitments(b.ledger, today: b.today).isEmpty)
    }

    // 5. Debt 80M + linked 80M cheque → one 80M outflow, not 160M.
    func testLinkedChequeIsNotDoubleCounted() throws {
        var b = B()
        b.account(opening: B.m(200))
        let p = b.contact("احمدی")
        let debt = b.obligation(.payable, B.m(80), contact: p, dueIn: 10)
        b.cheque(.issued, B.m(80), contact: p, dueIn: 12, obligation: debt)
        let f = try b.forecast(days: 30)
        let outflows = f.events.filter { $0.amount.isNegative }
        XCTAssertEqual(outflows.count, 1)
        XCTAssertEqual(try Money.sum(outflows.map(\.amount)), try B.m(80).negated())
        XCTAssertEqual(f.endBalance, B.m(120))
        XCTAssertEqual(try FinancialCalculator.position(b.ledger).payables, B.m(80))
    }

    func testPartialChequeLeavesResidualObligation() throws {
        var b = B()
        b.account(opening: B.m(200))
        let p = b.contact("احمدی")
        let debt = b.obligation(.payable, B.m(100), contact: p, dueIn: 20)
        b.cheque(.issued, B.m(80), contact: p, dueIn: 10, obligation: debt)
        let commitments = try CommitmentResolver.commitments(b.ledger, today: b.today)
        XCTAssertEqual(commitments.count, 2)
        XCTAssertEqual(try Money.sum(commitments.map(\.amount)), B.m(100))
    }

    // 6. Receivable 100M with 30M collected → 70M outstanding.
    func testPartialReceivableSettlement() throws {
        var b = B()
        let acc = b.account(opening: .zero)
        let p = b.contact("رضایی")
        let r = b.obligation(.receivable, B.m(100), contact: p, dueIn: 15)
        let tx = b.tx(.settlementIn, B.m(30), to: acc)
        b.settle(obligation: r, B.m(30), transaction: tx)
        XCTAssertEqual(try FinancialCalculator.outstanding(of: b.ledger.obligations[0], settlements: b.ledger.settlements), B.m(70))
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(30))
    }

    // 7. Settling a cheque in parts and refusing to over-settle.
    func testChequeMultiPartAndOverSettlementRejected() throws {
        var b = B()
        b.account(opening: B.m(500))
        let p = b.contact("کریمی")
        let ch = b.cheque(.issued, B.m(90), contact: p, dueIn: 3)
        b.settle(cheque: ch, B.m(30))
        b.settle(cheque: ch, B.m(40))
        XCTAssertEqual(try FinancialCalculator.outstanding(of: b.ledger.cheques[0], settlements: b.ledger.settlements), B.m(20))
        XCTAssertEqual(try FinancialCalculator.status(of: b.ledger.cheques[0], settlements: b.ledger.settlements, today: b.today), .partiallySettled)
        XCTAssertThrowsError(try LedgerRules.validateChequeSettlement(chequeId: ch, amount: B.m(25), in: b.ledger)) {
            XCTAssertEqual($0 as? DomainError, .exceedsOutstanding(remaining: B.m(20)))
        }
        XCTAssertNoThrow(try LedgerRules.validateChequeSettlement(chequeId: ch, amount: B.m(20), in: b.ledger))
    }

    // 8 (pure part). A voided settlement re-opens the cheque; a bounced cheque leaves the forecast.
    func testVoidedSettlementAndBouncedCheque() throws {
        var b = B()
        b.account(opening: B.m(10))
        let p = b.contact("کریمی")
        let debt = b.obligation(.receivable, B.m(50), contact: p, dueIn: 5)
        let ch = b.cheque(.received, B.m(50), contact: p, dueIn: 5, obligation: debt, lifecycle: .bounced)
        b.settle(cheque: ch, B.m(50), voided: true)
        XCTAssertEqual(try FinancialCalculator.outstanding(of: b.ledger.cheques[0], settlements: b.ledger.settlements), .zero)
        XCTAssertEqual(try FinancialCalculator.status(of: b.ledger.cheques[0], settlements: b.ledger.settlements, today: b.today), .bounced)
        // The obligation itself is open again and owns the full amount.
        let c = try CommitmentResolver.commitments(b.ledger, today: b.today)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].kind, .receivable)
        XCTAssertEqual(c[0].amount, B.m(50))
    }

    // 9. Offset only between opposite obligations of the same person.
    func testOffsetValidation() throws {
        var b = B()
        let p = b.contact("کریمی")
        let q = b.contact("حسینی")
        let r = b.obligation(.receivable, B.m(30), contact: p, dueIn: nil)
        let d = b.obligation(.payable, B.m(20), contact: p, dueIn: nil)
        let other = b.obligation(.payable, B.m(20), contact: q, dueIn: nil)
        XCTAssertNoThrow(try LedgerRules.validateOffset(receivableId: r, payableId: d, amount: B.m(20), in: b.ledger))
        XCTAssertThrowsError(try LedgerRules.validateOffset(receivableId: r, payableId: d, amount: B.m(25), in: b.ledger))
        XCTAssertThrowsError(try LedgerRules.validateOffset(receivableId: r, payableId: other, amount: B.m(5), in: b.ledger)) {
            XCTAssertEqual($0 as? DomainError, .invalidOffset)
        }
        b.settle(obligation: r, B.m(20), method: .offset)
        b.settle(obligation: d, B.m(20), method: .offset)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), .zero)
        let s = try FinancialCalculator.contactSummaries(b.ledger, today: b.today).first { $0.contact.id == p }!
        XCTAssertEqual(s.receivable, B.m(10))
        XCTAssertEqual(s.payable, .zero)
    }

    func testPersonWithBothSidesKeepsThemSeparate() throws {
        var b = B()
        let p = b.contact("کریمی")
        b.obligation(.receivable, B.m(30), contact: p, dueIn: 5)
        b.obligation(.payable, B.m(10), contact: p, dueIn: 5)
        let s = try FinancialCalculator.contactSummaries(b.ledger, today: b.today)[0]
        XCTAssertEqual(s.receivable, B.m(30))
        XCTAssertEqual(s.payable, B.m(10))
        XCTAssertEqual(s.net, B.m(20))
    }

    // 16 (pure part). Reversal restores balances and removes the expense from totals.
    func testReversalRestoresBalanceAndTotals() throws {
        var b = B()
        let acc = b.account(opening: B.m(50))
        let e = b.tx(.expense, B.m(5), from: acc)
        b.tx(.reversal, B.m(5), to: acc, reverses: e)
        XCTAssertEqual(try FinancialCalculator.totalCash(b.ledger), B.m(50))
        XCTAssertEqual(try FinancialCalculator.periodTotals(b.ledger, from: b.today, through: b.today).expense, .zero)
        XCTAssertThrowsError(try LedgerRules.validateReversal(transactionId: e, in: b.ledger)) {
            XCTAssertEqual($0 as? DomainError, .alreadyReversed)
        }
    }

    func testSafeToSpendSubtractsCertainOutflowsAndReserveOnly() throws {
        var b = B()
        b.account(opening: B.m(100))
        let p = b.contact("احمدی")
        b.cheque(.issued, B.m(30), contact: p, dueIn: 5)
        b.cheque(.issued, B.m(50), contact: p, dueIn: 40)       // outside the 30-day window
        b.obligation(.receivable, B.m(90), contact: p, dueIn: 3) // possible income is ignored
        let s = try FinancialCalculator.safeToSpend(b.ledger, today: b.today, horizonDays: 30, reserve: B.m(10))
        XCTAssertEqual(s.committedOutflows, B.m(30))
        XCTAssertEqual(s.amount, B.m(60))
        let negative = try FinancialCalculator.safeToSpend(b.ledger, today: b.today, horizonDays: 60, reserve: B.m(30))
        XCTAssertEqual(negative.amount, try B.m(-10))
    }
}

final class ForecastEngineTests: XCTestCase {
    typealias B = LedgerBuilder

    /// Golden scenario: 200M cash, 300M of cheques before day 25, 150M receivable on day 25.
    /// End balance is positive, but a temporary shortfall must be reported with date and amount.
    func testGoldenScenarioTemporaryShortfall() throws {
        var b = B()
        b.account(opening: B.m(200))
        let p = b.contact("احمدی")
        let q = b.contact("رضایی")
        b.cheque(.issued, B.m(100), contact: p, dueIn: 5)
        b.cheque(.issued, B.m(200), contact: p, dueIn: 10)
        b.obligation(.receivable, B.m(150), contact: q, dueIn: 25, confidence: .confirmed)
        let f = try b.forecast(days: 30)
        XCTAssertEqual(f.endBalance, B.m(50))
        XCTAssertTrue(f.endBalance.isPositive)
        XCTAssertEqual(f.firstShortfall?.date, b.today.adding(days: 10))
        XCTAssertEqual(f.requiredFunds, B.m(100))
        XCTAssertEqual(f.minimumDay?.endBalance, try B.m(-100))
        // Day 5 is still positive.
        XCTAssertEqual(f.days[5].endBalance, B.m(100))
    }

    // 14. Negative in the middle of the month even though the month ends positive.
    func testMidPeriodNegativeIsDetected() throws {
        var b = B()
        let acc = b.account(opening: B.m(10))
        _ = acc
        b.rule(.expense, B.m(15), start: b.today.adding(days: 3), frequency: .yearly)
        b.rule(.income, B.m(40), start: b.today.adding(days: 20), frequency: .yearly)
        let f = try b.forecast(days: 30)
        XCTAssertEqual(f.firstShortfall?.date, b.today.adding(days: 3))
        XCTAssertEqual(f.requiredFunds, B.m(5))
        XCTAssertEqual(f.endBalance, B.m(35))
    }

    func testReserveBreachReported() throws {
        var b = B()
        b.account(opening: B.m(50))
        let p = b.contact("احمدی")
        b.cheque(.issued, B.m(40), contact: p, dueIn: 2)
        let f = try b.forecast(days: 7, reserve: B.m(20))
        XCTAssertNil(f.firstShortfall)
        XCTAssertEqual(f.firstReserveBreach?.date, b.today.adding(days: 2))
        XCTAssertEqual(f.requiredForReserve, B.m(10))
    }

    // 10. Fixed monthly income + its real occurrence → no double count.
    func testRecurringIncomeConfirmedOccurrenceNotDoubleCounted() throws {
        var b = B()
        let acc = b.account(opening: B.m(10))
        let rule = b.rule(.income, B.m(30), start: b.today.adding(days: 2))
        let before = try b.forecast(days: 40)
        XCTAssertEqual(before.events.filter { $0.kind == .recurringIncome }.count, 2) // day 2 and ~day 32
        // The salary of day 2 arrives and is recorded against occurrence #0.
        b.tx(.income, B.m(30), to: acc, day: 2, recurrenceKey: RecurringSchedule.occurrenceKey(ruleId: rule, index: 0))
        let after = try b.forecast(days: 40)
        XCTAssertEqual(after.events.filter { $0.kind == .recurringIncome }.count, 1)
        // Starting balance already includes the real income; total over the window is identical.
        XCTAssertEqual(after.endBalance, before.endBalance)
    }

    // 11. Monthly due on day 31 in short months follows the policy.
    func testMonthlyRuleOnDay31() {
        let start = CivilDate(jalaliYear: 1405, month: 5, day: 31)!
        let rule = RecurringRuleSnapshot(
            id: UUID(), title: "اجاره", kind: .expense, amount: Money(rials: 10), accountId: nil, categoryId: nil,
            startDate: start, endDate: nil, frequency: .monthly, interval: 1, monthEndPolicy: .lastValidDay,
            isActive: true, confidence: .confirmed
        )
        let occ = RecurringSchedule.occurrences(of: rule, from: start, through: start.adding(days: 250))
        let dates = occ.map { $0.date.jalali }
        XCTAssertEqual(dates[0], JalaliDate(year: 1405, month: 5, day: 31))
        XCTAssertEqual(dates[1], JalaliDate(year: 1405, month: 6, day: 31))
        XCTAssertEqual(dates[2], JalaliDate(year: 1405, month: 7, day: 30))
        XCTAssertEqual(dates[7], JalaliDate(year: 1405, month: 12, day: 29))
        XCTAssertEqual(dates[8], JalaliDate(year: 1406, month: 1, day: 31))
        // Stable keys.
        XCTAssertEqual(occ[2].key, RecurringSchedule.occurrenceKey(ruleId: rule.id, index: 2))

        var next = rule
        next.monthEndPolicy = .firstDayOfNextMonth
        let occ2 = RecurringSchedule.occurrences(of: next, from: start, through: start.adding(days: 100))
        XCTAssertEqual(occ2[2].date.jalali, JalaliDate(year: 1405, month: 8, day: 1))
    }

    func testUndatedObligationIsNotPlacedOnAGuessedDate() throws {
        var b = B()
        b.account(opening: B.m(10))
        let p = b.contact("احمدی")
        b.obligation(.payable, B.m(50), contact: p, dueIn: nil)
        let f = try b.forecast(days: 90)
        XCTAssertTrue(f.events.isEmpty)
        XCTAssertNil(f.firstShortfall)
        XCTAssertEqual(f.undated.count, 1)
    }

    func testScenarioInclusionRules() throws {
        var b = B()
        b.account(opening: .zero)
        let p = b.contact("رضایی")
        b.obligation(.receivable, B.m(10), contact: p, dueIn: 3, confidence: .confirmed)
        b.obligation(.receivable, B.m(20), contact: p, dueIn: 3, confidence: .expected)
        b.obligation(.receivable, B.m(40), contact: p, dueIn: 3, confidence: .uncertain)
        XCTAssertEqual(try b.forecast(days: 10, scenario: .conservative).endBalance, B.m(10))
        XCTAssertEqual(try b.forecast(days: 10, scenario: .normal).endBalance, B.m(30))
        XCTAssertEqual(try b.forecast(days: 10, scenario: .optimistic).endBalance, B.m(70))
    }

    func testOverduePayableCountsToday() throws {
        var b = B()
        b.account(opening: B.m(5))
        let p = b.contact("احمدی")
        b.obligation(.payable, B.m(8), contact: p, dueIn: -4)
        let f = try b.forecast(days: 7)
        XCTAssertEqual(f.firstShortfall?.date, b.today)
        XCTAssertTrue(f.events[0].wasOverdue)
    }

    // 15. No expense recorded on a day means "no data", not "zero spending".
    func testMissingRecordsAreNoDataNotZero() throws {
        var b = B()
        let acc = b.account(opening: B.m(100))
        b.tx(.expense, B.m(1), from: acc, day: -3)
        let stats = try SpendingAnalyzer.stats(b.ledger, today: b.today)
        XCTAssertEqual(stats.daysSinceLastExpense, 3)
        XCTAssertNil(stats.average7, "Too little history: no average instead of a misleading one")
        let insights = try InsightEngine.insights(ledger: b.ledger, today: b.today, unit: .toman, upcoming: [], spending: stats)
        let nudge = insights.first { $0.id == "no-record" }
        XCTAssertNotNil(nudge)
        XCTAssertTrue(nudge!.text.contains("ثبت نکرده‌ای"))
        let f = try b.forecast(days: 7, spending: true)
        XCTAssertTrue(f.assumptions.contains { $0.contains("داده کافی") })
    }

    func testDailySpendingEstimateFromBudget() throws {
        var b = B()
        b.account(opening: B.m(100))
        b.ledger.monthlyBudget = B.m(30)
        let f = try b.forecast(days: 10, scenario: .normal, spending: true)
        XCTAssertEqual(f.endBalance, B.m(90))
        let c = try b.forecast(days: 10, scenario: .conservative, spending: true)
        XCTAssertEqual(c.endBalance, B.m(88))
    }

    func testInsightMentionsUpcomingCheque() throws {
        var b = B()
        b.account(opening: B.m(100))
        let p = b.contact("احمدی")
        b.cheque(.issued, B.m(75), contact: p, dueIn: 3)
        let due = try DashboardBuilder.dueItems(b.ledger, today: b.today, withinDays: 30)
        let stats = try SpendingAnalyzer.stats(b.ledger, today: b.today)
        let insights = try InsightEngine.insights(ledger: b.ledger, today: b.today, unit: .toman, upcoming: due, spending: stats)
        XCTAssertTrue(insights.contains { $0.text.contains("۳ روز دیگر چکی به احمدی به مبلغ ۷۵٬۰۰۰٬۰۰۰ تومان داری") })
    }

    func testNinetyDayHorizonPerformance() throws {
        var b = B()
        let acc = b.account(opening: B.m(1_000))
        for i in 0..<2_000 { b.tx(.expense, B.t(10_000), from: acc, day: -(i % 300)) }
        measure {
            _ = try? b.forecast(days: 90, spending: true)
        }
    }
}
