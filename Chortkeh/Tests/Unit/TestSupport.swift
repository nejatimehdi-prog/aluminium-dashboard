import Foundation
@testable import Chortkeh

/// Builds pure ledgers for engine tests without any database.
struct LedgerBuilder {
    var ledger = LedgerSnapshot()
    let today: CivilDate

    init(today: CivilDate = CivilDate(jalaliYear: 1405, month: 8, day: 16)!) {
        self.today = today
    }

    static func t(_ toman: Int64) -> Money { try! Money.toman(toman) }
    static func m(_ millionToman: Int64) -> Money { try! Money.toman(millionToman * 1_000_000) }

    @discardableResult
    mutating func account(_ name: String = "ملت", opening: Money) -> UUID {
        let id = UUID()
        ledger.accounts.append(AccountSnapshot(id: id, name: name, kind: .bank, openingBalance: opening, isActive: true,
                                               sortOrder: ledger.accounts.count))
        return id
    }

    @discardableResult
    mutating func contact(_ name: String) -> UUID {
        let id = UUID()
        ledger.contacts.append(ContactSnapshot(id: id, name: name, phone: "", note: ""))
        return id
    }

    @discardableResult
    mutating func tx(_ kind: TransactionKind, _ amount: Money, from: UUID? = nil, to: UUID? = nil, day: Int = 0,
                     reverses: UUID? = nil, recurrenceKey: String? = nil) -> UUID {
        let id = UUID()
        ledger.transactions.append(TransactionSnapshot(
            id: id, kind: kind, amount: amount, date: today.adding(days: day), fromAccountId: from, toAccountId: to,
            contactId: nil, categoryId: nil, note: "", reversesTransactionId: reverses, recurrenceKey: recurrenceKey,
            eventGroupId: UUID(), chequeId: nil, obligationId: nil, createdAt: Date()
        ))
        return id
    }

    @discardableResult
    mutating func obligation(_ direction: ObligationDirection, _ amount: Money, contact: UUID, dueIn: Int?,
                             confidence: ReceiptConfidence = .confirmed) -> UUID {
        let id = UUID()
        ledger.obligations.append(ObligationSnapshot(
            id: id, direction: direction, contactId: contact, principal: amount, dueDate: dueIn.map { today.adding(days: $0) },
            createdOn: today, isCancelled: false, confidence: confidence, note: "", createdAt: Date()
        ))
        return id
    }

    @discardableResult
    mutating func cheque(_ direction: ChequeDirection, _ amount: Money, contact: UUID, dueIn: Int, obligation: UUID? = nil,
                         confidence: ReceiptConfidence = .confirmed, lifecycle: ChequeLifecycle = .active) -> UUID {
        let id = UUID()
        ledger.cheques.append(ChequeSnapshot(
            id: id, direction: direction, amount: amount, dueDate: today.adding(days: dueIn), contactId: contact,
            bankName: "", accountId: nil, chequeNumber: "", sayadId: "", lifecycle: lifecycle, obligationId: obligation,
            confidence: confidence, note: "", createdAt: Date()
        ))
        return id
    }

    mutating func settle(obligation: UUID? = nil, cheque: UUID? = nil, _ amount: Money, transaction: UUID? = nil,
                         method: SettlementMethod = .cash, voided: Bool = false) {
        ledger.settlements.append(SettlementSnapshot(
            id: UUID(), obligationId: obligation, chequeId: cheque, amount: amount, date: today, method: method,
            transactionId: transaction, groupId: UUID(), isVoided: voided
        ))
    }

    @discardableResult
    mutating func rule(_ kind: TransactionKind, _ amount: Money, start: CivilDate, frequency: RecurrenceFrequency = .monthly,
                       policy: MonthEndPolicy = .lastValidDay, end: CivilDate? = nil) -> UUID {
        let id = UUID()
        ledger.recurringRules.append(RecurringRuleSnapshot(
            id: id, title: "قاعده", kind: kind, amount: amount, accountId: ledger.accounts.first?.id, categoryId: nil,
            startDate: start, endDate: end, frequency: frequency, interval: 1, monthEndPolicy: policy, isActive: true,
            confidence: .confirmed
        ))
        return id
    }

    func forecast(days: Int, scenario: ForecastScenario = .normal, reserve: Money = .zero, spending: Bool = false) throws -> ForecastResult {
        try ForecastEngine.run(ForecastInput(ledger: ledger, today: today, horizonDays: days, scenario: scenario,
                                             reserve: reserve, includeDailySpending: spending))
    }
}
