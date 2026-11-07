import Foundation

/// Integrity rules checked before anything is written. Pure functions over a `LedgerSnapshot`.
enum LedgerRules {
    static func requirePositive(_ amount: Money) throws {
        guard amount.isPositive else { throw DomainError.amountMustBePositive }
        guard amount.rials <= Money.maxInputRials else { throw DomainError.amountOutOfRange }
    }

    static func requireActiveAccount(_ id: UUID?, in ledger: LedgerSnapshot) throws -> AccountSnapshot {
        guard let id else { throw DomainError.accountRequired }
        guard let account = ledger.account(id) else { throw DomainError.accountNotFound }
        guard account.isActive else { throw DomainError.accountInactive }
        return account
    }

    static func validateTransfer(amount: Money, from: UUID?, to: UUID?, in ledger: LedgerSnapshot) throws {
        try requirePositive(amount)
        let a = try requireActiveAccount(from, in: ledger)
        let b = try requireActiveAccount(to, in: ledger)
        guard a.id != b.id else { throw DomainError.sameAccountTransfer }
    }

    /// A settlement may never exceed what is still outstanding.
    static func validateSettlement(amount: Money, outstanding: Money) throws {
        try requirePositive(amount)
        guard outstanding.isPositive else { throw DomainError.nothingOutstanding }
        guard amount <= outstanding else { throw DomainError.exceedsOutstanding(remaining: outstanding) }
    }

    static func validateObligationSettlement(obligationId: UUID, amount: Money, in ledger: LedgerSnapshot) throws -> ObligationSnapshot {
        guard let obligation = ledger.obligation(obligationId) else { throw DomainError.notFound }
        guard !obligation.isCancelled else { throw DomainError.nothingOutstanding }
        let outstanding = try FinancialCalculator.outstanding(of: obligation, settlements: ledger.settlements)
        try validateSettlement(amount: amount, outstanding: outstanding)
        return obligation
    }

    static func validateChequeSettlement(chequeId: UUID, amount: Money, in ledger: LedgerSnapshot) throws -> ChequeSnapshot {
        guard let cheque = ledger.cheque(chequeId) else { throw DomainError.notFound }
        guard cheque.lifecycle == .active else { throw DomainError.chequeNotActive }
        let outstanding = try FinancialCalculator.outstanding(of: cheque, settlements: ledger.settlements)
        try validateSettlement(amount: amount, outstanding: outstanding)
        // If linked to an obligation, the obligation must also be able to absorb the amount.
        if let obligation = ledger.obligation(cheque.obligationId), !obligation.isCancelled {
            let obligationOutstanding = try FinancialCalculator.outstanding(of: obligation, settlements: ledger.settlements)
            if amount > obligationOutstanding {
                throw DomainError.exceedsOutstanding(remaining: obligationOutstanding)
            }
        }
        return cheque
    }

    static func validateReversal(transactionId: UUID, in ledger: LedgerSnapshot) throws -> TransactionSnapshot {
        guard let tx = ledger.transaction(transactionId) else { throw DomainError.notFound }
        guard tx.kind != .reversal else { throw DomainError.cannotReverseReversal }
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        guard !reversed.contains(tx.id) else { throw DomainError.alreadyReversed }
        return tx
    }

    /// Offset (تهاتر) is allowed only between an open receivable and an open payable of the same person,
    /// for at most the smaller outstanding amount.
    static func validateOffset(receivableId: UUID, payableId: UUID, amount: Money, in ledger: LedgerSnapshot) throws {
        try requirePositive(amount)
        guard let r = ledger.obligation(receivableId), let p = ledger.obligation(payableId) else {
            throw DomainError.notFound
        }
        guard r.direction == .receivable, p.direction == .payable,
              r.contactId == p.contactId, !r.isCancelled, !p.isCancelled
        else { throw DomainError.invalidOffset }
        let ro = try FinancialCalculator.outstanding(of: r, settlements: ledger.settlements)
        let po = try FinancialCalculator.outstanding(of: p, settlements: ledger.settlements)
        let limit = Swift.min(ro, po)
        try validateSettlement(amount: amount, outstanding: limit)
    }

    /// Records that other records depend on. Deleting them silently is forbidden.
    static func dependencies(ofContact id: UUID, in ledger: LedgerSnapshot) -> [String] {
        var deps: [String] = []
        if ledger.obligations.contains(where: { $0.contactId == id }) { deps.append("طلب/بدهی") }
        if ledger.cheques.contains(where: { $0.contactId == id }) { deps.append("چک") }
        if ledger.transactions.contains(where: { $0.contactId == id }) { deps.append("تراکنش") }
        return deps
    }

    static func dependencies(ofAccount id: UUID, in ledger: LedgerSnapshot) -> [String] {
        var deps: [String] = []
        if ledger.transactions.contains(where: { $0.fromAccountId == id || $0.toAccountId == id }) { deps.append("تراکنش") }
        if ledger.cheques.contains(where: { $0.accountId == id }) { deps.append("چک") }
        if ledger.recurringRules.contains(where: { $0.accountId == id }) { deps.append("قاعده تکرار") }
        return deps
    }
}
