import Foundation

struct PositionSummary: Equatable, Sendable {
    var hasAccounts: Bool
    /// Sum of real balances of active accounts.
    var cash: Money
    /// Open receivables (obligations + received cheques not linked to an obligation).
    var receivables: Money
    /// Open payables (obligations + issued cheques not linked to an obligation).
    var payables: Money
    /// cash + receivables − payables. Informational only; NOT spendable money.
    var netPosition: Money
}

struct SafeToSpend: Equatable, Sendable {
    var cash: Money
    var committedOutflows: Money
    var reserve: Money
    var horizonDays: Int
    /// cash − committed dated outflows within the horizon − reserve. May be negative.
    var amount: Money
}

struct PeriodTotals: Equatable, Sendable {
    var income: Money
    var expense: Money
    var expenseByCategory: [UUID?: Money]
}

struct ContactSummary: Identifiable, Equatable, Sendable {
    var id: UUID { contact.id }
    var contact: ContactSnapshot
    var receivable: Money
    var payable: Money
    var overdue: Money
    var nearestDue: CivilDate?
    /// receivable − payable; informational only, never settles anything automatically.
    var net: Money
}

enum DueTiming: Equatable, Sendable {
    case overdue(days: Int)
    case dueSoon(days: Int)
    case later(days: Int)
    case undated
}

/// Core money calculations. Independent of persistence and UI.
enum FinancialCalculator {
    static let dueSoonDays = 7

    // MARK: Balances

    /// Every transaction moves `amount` out of `fromAccountId` and into `toAccountId`.
    /// Reversals are stored with swapped accounts, so the same rule applies to them.
    static func accountBalances(_ ledger: LedgerSnapshot) throws -> [UUID: Money] {
        var balances: [UUID: Money] = [:]
        for account in ledger.accounts {
            balances[account.id] = account.openingBalance
        }
        for tx in ledger.transactions {
            if let from = tx.fromAccountId {
                balances[from] = try (balances[from] ?? .zero) - tx.amount
            }
            if let to = tx.toAccountId {
                balances[to] = try (balances[to] ?? .zero) + tx.amount
            }
        }
        return balances
    }

    static func balance(of accountId: UUID, in ledger: LedgerSnapshot) throws -> Money {
        try accountBalances(ledger)[accountId] ?? .zero
    }

    static func totalCash(_ ledger: LedgerSnapshot) throws -> Money {
        let balances = try accountBalances(ledger)
        return try Money.sum(ledger.accounts.filter(\.isActive).map { balances[$0.id] ?? .zero })
    }

    /// IDs of transactions that have been reversed (they and their reversal net to zero).
    static func reversedTransactionIds(_ ledger: LedgerSnapshot) -> Set<UUID> {
        Set(ledger.transactions.compactMap { $0.kind == .reversal ? $0.reversesTransactionId : nil })
    }

    // MARK: Outstanding amounts

    static func settled(obligationId: UUID, settlements: [SettlementSnapshot]) throws -> Money {
        try Money.sum(settlements.filter { $0.obligationId == obligationId && !$0.isVoided }.map(\.amount))
    }

    static func settled(chequeId: UUID, settlements: [SettlementSnapshot]) throws -> Money {
        try Money.sum(settlements.filter { $0.chequeId == chequeId && !$0.isVoided }.map(\.amount))
    }

    /// Remaining amount = principal − valid settlements. Derived, never stored, so there is one source of truth.
    static func outstanding(of obligation: ObligationSnapshot, settlements: [SettlementSnapshot]) throws -> Money {
        if obligation.isCancelled { return .zero }
        return try obligation.principal - settled(obligationId: obligation.id, settlements: settlements)
    }

    static func outstanding(of cheque: ChequeSnapshot, settlements: [SettlementSnapshot]) throws -> Money {
        guard cheque.lifecycle == .active else { return .zero }
        return try cheque.amount - settled(chequeId: cheque.id, settlements: settlements)
    }

    static func timing(due: CivilDate?, today: CivilDate) -> DueTiming {
        guard let due else { return .undated }
        let days = today.days(until: due)
        if days < 0 { return .overdue(days: -days) }
        if days <= dueSoonDays { return .dueSoon(days: days) }
        return .later(days: days)
    }

    static func status(of cheque: ChequeSnapshot, settlements: [SettlementSnapshot], today: CivilDate) throws -> ChequeStatus {
        switch cheque.lifecycle {
        case .bounced: return .bounced
        case .cancelled: return .cancelled
        case .returned: return .returned
        case .active: break
        }
        let settledAmount = try settled(chequeId: cheque.id, settlements: settlements)
        if settledAmount >= cheque.amount { return .settled }
        if settledAmount.isPositive { return .partiallySettled }
        switch timing(due: cheque.dueDate, today: today) {
        case .overdue: return .overdue
        case .dueSoon: return .dueSoon
        default: return .open
        }
    }

    // MARK: Position

    static func position(_ ledger: LedgerSnapshot) throws -> PositionSummary {
        let cash = try totalCash(ledger)
        var receivables = Money.zero
        var payables = Money.zero
        for o in ledger.obligations where !o.isCancelled {
            let out = try outstanding(of: o, settlements: ledger.settlements)
            guard out.isPositive else { continue }
            if o.direction == .receivable { receivables = try receivables + out } else { payables = try payables + out }
        }
        for c in ledger.cheques where c.obligationId == nil || ledger.obligation(c.obligationId)?.isCancelled == true {
            let out = try outstanding(of: c, settlements: ledger.settlements)
            guard out.isPositive else { continue }
            if c.direction == .received { receivables = try receivables + out } else { payables = try payables + out }
        }
        let net = try cash + receivables - payables
        return PositionSummary(
            hasAccounts: !ledger.accounts.isEmpty,
            cash: cash,
            receivables: receivables,
            payables: payables,
            netPosition: net
        )
    }

    /// "How much can I safely spend?" — cash minus certain dated outflows within the horizon minus reserve.
    /// Possible incoming money is deliberately ignored here.
    static func safeToSpend(_ ledger: LedgerSnapshot, today: CivilDate, horizonDays: Int, reserve: Money) throws -> SafeToSpend {
        let cash = try totalCash(ledger)
        let end = today.adding(days: horizonDays)
        var committed = Money.zero
        for c in try CommitmentResolver.commitments(ledger, today: today) where c.flow == .outflow {
            guard let due = c.dueDate, due <= end else { continue }
            committed = try committed + c.amount
        }
        for occ in try RecurringSchedule.pendingOccurrences(ledger, from: today, through: end) where occ.rule.kind == .expense {
            committed = try committed + occ.rule.amount
        }
        let amount = try cash - committed - reserve
        return SafeToSpend(cash: cash, committedOutflows: committed, reserve: reserve, horizonDays: horizonDays, amount: amount)
    }

    // MARK: Period totals

    /// Real income and expense in [from, through]. Transfers, settlements, adjustments, and reversed pairs are excluded.
    static func periodTotals(_ ledger: LedgerSnapshot, from: CivilDate, through: CivilDate) throws -> PeriodTotals {
        let reversed = reversedTransactionIds(ledger)
        var income = Money.zero
        var expense = Money.zero
        var byCategory: [UUID?: Money] = [:]
        for tx in ledger.transactions where tx.date >= from && tx.date <= through && !reversed.contains(tx.id) {
            switch tx.kind {
            case .income:
                income = try income + tx.amount
            case .expense:
                expense = try expense + tx.amount
                byCategory[tx.categoryId] = try (byCategory[tx.categoryId] ?? .zero) + tx.amount
            default:
                break
            }
        }
        return PeriodTotals(income: income, expense: expense, expenseByCategory: byCategory)
    }

    // MARK: People

    static func contactSummaries(_ ledger: LedgerSnapshot, today: CivilDate) throws -> [ContactSummary] {
        let commitments = try CommitmentResolver.commitments(ledger, today: today)
        var result: [ContactSummary] = []
        for contact in ledger.contacts {
            var receivable = Money.zero
            var payable = Money.zero
            var overdue = Money.zero
            var nearest: CivilDate?
            for c in commitments where c.contactId == contact.id {
                if c.flow == .inflow { receivable = try receivable + c.amount } else { payable = try payable + c.amount }
                if let due = c.dueDate {
                    if due < today { overdue = try overdue + c.amount }
                    if nearest == nil || due < nearest! { nearest = due }
                }
            }
            result.append(ContactSummary(
                contact: contact,
                receivable: receivable,
                payable: payable,
                overdue: overdue,
                nearestDue: nearest,
                net: try receivable - payable
            ))
        }
        return result.sorted { ($0.receivable.rials + $0.payable.rials) > ($1.receivable.rials + $1.payable.rials) }
    }
}
