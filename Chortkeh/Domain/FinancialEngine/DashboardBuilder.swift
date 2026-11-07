import Foundation

struct DueItem: Identifiable, Hashable, Sendable {
    var id: String { ownerId }
    let ownerId: String
    let sourceId: UUID
    let kind: CommitmentKind
    let flow: CashFlowDirection
    let amount: Money
    let dueDate: CivilDate
    let daysLeft: Int
    let contactName: String?
    var isOverdue: Bool { daysLeft < 0 }
}

enum InsightSeverity: Int, Comparable, Sendable {
    case info = 0
    case notice = 1
    case warning = 2

    static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum InsightAction: Hashable, Sendable {
    case recordExpense
    case openCommitment(ownerId: String)
    case openForecast
    case none
}

struct Insight: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let severity: InsightSeverity
    let action: InsightAction
}

enum ActivityFlow: Sendable {
    case inflow
    case outflow
    case neutral
}

enum ActivityKind: String, CaseIterable, Sendable {
    case transaction
    case obligation
    case cheque

    var title: String {
        switch self {
        case .transaction: return "تراکنش"
        case .obligation: return "طلب/بدهی"
        case .cheque: return "چک"
        }
    }
}

struct ActivityItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: ActivityKind
    let date: CivilDate
    let createdAt: Date
    let title: String
    let subtitle: String
    let amount: Money
    let flow: ActivityFlow
    let isReversed: Bool
    let searchText: String
}

struct MonthSummary: Sendable {
    let title: String
    let income: Money
    let expense: Money
    let previousIncome: Money
    let previousExpense: Money
    let previousTitle: String
    let daysElapsed: Int
    let daysWithExpenseRecords: Int
}

struct AccountBalance: Identifiable, Sendable {
    var id: UUID { account.id }
    let account: AccountSnapshot
    let balance: Money
}

struct DashboardData: Sendable {
    var today: CivilDate
    var position: PositionSummary
    var accountBalances: [AccountBalance]
    var safeToSpend: SafeToSpend
    var forecast: ForecastResult
    var insights: [Insight]
    var upcoming: [DueItem]
    var month: MonthSummary
    var recent: [ActivityItem]
    var spending: SpendingStats
}

struct DashboardRequest: Sendable {
    var ledger: LedgerSnapshot
    var today: CivilDate
    var horizonDays: Int
    var scenario: ForecastScenario
    var reserve: Money
    var unit: CurrencyUnit
    var upcomingWindowDays: Int = 30
    var recentLimit: Int = 10
}

enum DashboardBuilder {
    static func build(_ r: DashboardRequest) throws -> DashboardData {
        let ledger = r.ledger
        let position = try FinancialCalculator.position(ledger)
        let balances = try FinancialCalculator.accountBalances(ledger)
        let accounts = ledger.accounts
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
            .map { AccountBalance(account: $0, balance: balances[$0.id] ?? .zero) }
        let safe = try FinancialCalculator.safeToSpend(ledger, today: r.today, horizonDays: r.horizonDays, reserve: r.reserve)
        let forecast = try ForecastEngine.run(ForecastInput(
            ledger: ledger, today: r.today, horizonDays: r.horizonDays, scenario: r.scenario, reserve: r.reserve
        ))
        let upcoming = try dueItems(ledger, today: r.today, withinDays: r.upcomingWindowDays)
        let spending = try SpendingAnalyzer.stats(ledger, today: r.today)
        let insights = try InsightEngine.insights(
            ledger: ledger, today: r.today, unit: r.unit, upcoming: upcoming, spending: spending
        )
        return DashboardData(
            today: r.today,
            position: position,
            accountBalances: accounts,
            safeToSpend: safe,
            forecast: forecast,
            insights: insights,
            upcoming: upcoming,
            month: try monthSummary(ledger, today: r.today),
            recent: Array(activities(ledger).prefix(r.recentLimit)),
            spending: spending
        )
    }

    /// Open dated commitments due within `withinDays` (overdue ones included), nearest first.
    static func dueItems(_ ledger: LedgerSnapshot, today: CivilDate, withinDays: Int) throws -> [DueItem] {
        let end = today.adding(days: withinDays)
        return try CommitmentResolver.commitments(ledger, today: today).compactMap { c -> DueItem? in
            guard let due = c.dueDate, due <= end else { return nil }
            return DueItem(
                ownerId: c.ownerId,
                sourceId: c.sourceId,
                kind: c.kind,
                flow: c.flow,
                amount: c.amount,
                dueDate: due,
                daysLeft: today.days(until: due),
                contactName: ledger.contact(c.contactId)?.name
            )
        }
    }

    static func monthSummary(_ ledger: LedgerSnapshot, today: CivilDate) throws -> MonthSummary {
        let start = today.startOfJalaliMonth
        let previousStart = start.adding(days: -1).startOfJalaliMonth
        let current = try FinancialCalculator.periodTotals(ledger, from: start, through: today)
        let previous = try FinancialCalculator.periodTotals(ledger, from: previousStart, through: start.adding(days: -1))
        let expenseDays = Set(ledger.transactions
            .filter { $0.kind == .expense && $0.date >= start && $0.date <= today }
            .map(\.date)).count
        return MonthSummary(
            title: PersianFormat.monthTitle(today),
            income: current.income,
            expense: current.expense,
            previousIncome: previous.income,
            previousExpense: previous.expense,
            previousTitle: PersianFormat.monthTitle(previousStart),
            daysElapsed: start.days(until: today) + 1,
            daysWithExpenseRecords: expenseDays
        )
    }

    /// Unified, newest-first activity feed used for "recent events" and search.
    static func activities(_ ledger: LedgerSnapshot) -> [ActivityItem] {
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        var items: [ActivityItem] = []
        for tx in ledger.transactions {
            let flow: ActivityFlow
            switch tx.kind {
            case .income, .settlementIn, .adjustmentIn: flow = .inflow
            case .expense, .settlementOut, .adjustmentOut: flow = .outflow
            case .transfer, .reversal: flow = .neutral
            }
            let contact = ledger.contact(tx.contactId)?.name
            let category = ledger.category(tx.categoryId)?.name
            var subtitleParts: [String] = []
            if tx.kind == .transfer {
                let from = ledger.account(tx.fromAccountId)?.name ?? "؟"
                let to = ledger.account(tx.toAccountId)?.name ?? "؟"
                subtitleParts.append("\(from) ← \(to)")
            } else if let name = ledger.account(tx.fromAccountId ?? tx.toAccountId)?.name {
                subtitleParts.append(name)
            }
            if let contact { subtitleParts.append(contact) }
            if let category { subtitleParts.append(category) }
            let title = tx.note.isEmpty ? (category ?? tx.kind.title) : tx.note
            items.append(ActivityItem(
                id: tx.id,
                kind: .transaction,
                date: tx.date,
                createdAt: tx.createdAt,
                title: tx.kind == .reversal ? "برگشت: \(title)" : title,
                subtitle: ([tx.kind.title] + subtitleParts).joined(separator: " · "),
                amount: tx.amount,
                flow: flow,
                isReversed: reversed.contains(tx.id),
                searchText: ([title, tx.note, tx.kind.title] + subtitleParts).joined(separator: " ")
            ))
        }
        for o in ledger.obligations {
            let name = ledger.contact(o.contactId)?.name ?? ""
            let title = o.direction == .receivable ? "طلب از \(name)" : "بدهی به \(name)"
            items.append(ActivityItem(
                id: o.id,
                kind: .obligation,
                date: o.createdOn,
                createdAt: o.createdAt,
                title: title,
                subtitle: o.dueDate.map { "سررسید \(PersianFormat.date($0))" } ?? "بدون سررسید مشخص",
                amount: o.principal,
                flow: .neutral,
                isReversed: o.isCancelled,
                searchText: [title, o.note, name].joined(separator: " ")
            ))
        }
        for c in ledger.cheques {
            let name = ledger.contact(c.contactId)?.name ?? ""
            let title = c.direction == .issued ? "چک به \(name)" : "چک از \(name)"
            items.append(ActivityItem(
                id: c.id,
                kind: .cheque,
                date: c.dueDate,
                createdAt: c.createdAt,
                title: title,
                subtitle: "سررسید \(PersianFormat.date(c.dueDate))" + (c.bankName.isEmpty ? "" : " · \(c.bankName)"),
                amount: c.amount,
                flow: .neutral,
                isReversed: c.lifecycle != .active,
                searchText: [title, c.note, name, c.bankName, c.chequeNumber, c.sayadId].joined(separator: " ")
            ))
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// Search over the activity feed. Persian/Arabic letter variants (ي/ی، ك/ک) and digits are normalized.
    static func search(_ items: [ActivityItem], text: String, kind: ActivityKind?, from: CivilDate?, through: CivilDate?) -> [ActivityItem] {
        let needle = normalizeForSearch(text)
        return items.filter { item in
            if let kind, item.kind != kind { return false }
            if let from, item.date < from { return false }
            if let through, item.date > through { return false }
            if needle.isEmpty { return true }
            if normalizeForSearch(item.searchText).contains(needle) { return true }
            // Amount search: digits typed by the user matched against the amount in toman or rial.
            let digitsOnly = AmountInputParser.normalizeDigits(text).filter { $0.isASCII && $0.isNumber }
            if !digitsOnly.isEmpty {
                return String(item.amount.rials / 10).contains(digitsOnly) || String(item.amount.rials).contains(digitsOnly)
            }
            return false
        }
    }

    static func normalizeForSearch(_ text: String) -> String {
        AmountInputParser.normalizeDigits(text)
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "\u{200C}", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
