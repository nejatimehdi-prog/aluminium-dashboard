import Foundation

/// Rule-based "what's up today?" messages. Local only — no cloud AI.
enum InsightEngine {
    static let noRecordNudgeDays = 2

    static func insights(
        ledger: LedgerSnapshot,
        today: CivilDate,
        unit: CurrencyUnit,
        upcoming: [DueItem],
        spending: SpendingStats
    ) throws -> [Insight] {
        var result: [Insight] = []
        func money(_ m: Money) -> String { PersianFormat.money(m, unit: unit) }

        // Overdue items.
        let overdue = upcoming.filter(\.isOverdue)
        let overduePay = overdue.filter { $0.flow == .outflow }
        let overdueGet = overdue.filter { $0.flow == .inflow }
        if !overduePay.isEmpty {
            let total = try Money.sum(overduePay.map(\.amount))
            result.append(Insight(
                id: "overdue-out",
                text: "\(PersianFormat.number(overduePay.count)) پرداخت سررسیدگذشته داری؛ جمعاً \(money(total)).",
                severity: .warning,
                action: .openCommitment(ownerId: overduePay[0].ownerId)
            ))
        }
        if !overdueGet.isEmpty {
            let total = try Money.sum(overdueGet.map(\.amount))
            result.append(Insight(
                id: "overdue-in",
                text: "\(PersianFormat.number(overdueGet.count)) طلب یا چک سررسیدگذشته هنوز وصول نشده؛ جمعاً \(money(total)).",
                severity: .notice,
                action: .openCommitment(ownerId: overdueGet[0].ownerId)
            ))
        }

        // Nearest upcoming payment (within 7 days).
        let soonPay = upcoming.filter { $0.flow == .outflow && $0.daysLeft >= 0 && $0.daysLeft <= 7 }
        if let next = soonPay.first {
            let what = next.kind == .chequeIssued ? "چکی" : "پرداختی"
            let who = next.contactName.map { " به \($0)" } ?? ""
            let when = next.daysLeft == 0 ? "امروز" : (next.daysLeft == 1 ? "فردا" : "\(PersianFormat.number(next.daysLeft)) روز دیگر")
            result.append(Insight(
                id: "next-out",
                text: "\(when) \(what)\(who) به مبلغ \(money(next.amount)) داری.",
                severity: next.daysLeft <= 1 ? .warning : .notice,
                action: .openCommitment(ownerId: next.ownerId)
            ))
            if soonPay.count > 1 {
                let total = try Money.sum(soonPay.map(\.amount))
                result.append(Insight(
                    id: "week-out",
                    text: "در ۷ روز آینده \(PersianFormat.number(soonPay.count)) پرداخت به جمع \(money(total)) داری.",
                    severity: .info,
                    action: .openForecast
                ))
            }
        }

        // Expected receipts within 7 days.
        let soonGet = upcoming.filter { $0.flow == .inflow && $0.daysLeft >= 0 && $0.daysLeft <= 7 }
        if !soonGet.isEmpty {
            let total = try Money.sum(soonGet.map(\.amount))
            result.append(Insight(
                id: "week-in",
                text: "در ۷ روز آینده \(money(total)) طلب یا چک منتظر وصول است.",
                severity: .info,
                action: .openCommitment(ownerId: soonGet[0].ownerId)
            ))
        }

        // Liquidity need for certain payments in the next 7 days (conservative scenario, no estimates).
        if !ledger.accounts.isEmpty {
            let conservative = try ForecastEngine.run(ForecastInput(
                ledger: ledger, today: today, horizonDays: 7, scenario: .conservative, reserve: .zero, includeDailySpending: false
            ))
            if let shortfall = conservative.firstShortfall {
                result.append(Insight(
                    id: "need-cash",
                    text: "برای پوشش پرداخت‌های قطعی ۷ روز آینده \(money(conservative.requiredFunds)) کم داری (از \(PersianFormat.date(shortfall.date, style: .dayMonth))).",
                    severity: .warning,
                    action: .openForecast
                ))
            }
        }

        // Missing expense records: "no data", never "zero spending".
        if !ledger.accounts.isEmpty {
            if let since = spending.daysSinceLastExpense {
                if since >= noRecordNudgeDays {
                    result.append(Insight(
                        id: "no-record",
                        text: "در \(PersianFormat.number(since)) روز گذشته هزینه‌ای ثبت نکرده‌ای؛ می‌خواهی ثبت کنی؟",
                        severity: .info,
                        action: .recordExpense
                    ))
                }
            } else {
                result.append(Insight(
                    id: "no-record",
                    text: "هنوز هزینه‌ای ثبت نکرده‌ای. با «+ ثبت سریع» اولین هزینه را ثبت کن.",
                    severity: .info,
                    action: .recordExpense
                ))
            }
        }

        return result.sorted { $0.severity > $1.severity }
    }
}
