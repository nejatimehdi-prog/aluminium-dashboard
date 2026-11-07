import Foundation

// Pure value types consumed by the financial and forecast engines.
// They mirror the persistent models but have no dependency on SwiftData or SwiftUI.

enum AccountKind: String, Codable, CaseIterable, Sendable {
    case bank
    case cash

    var title: String {
        switch self {
        case .bank: return "بانکی"
        case .cash: return "نقدی"
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case income
    case expense
    case transfer
    case settlementIn
    case settlementOut
    case adjustmentIn
    case adjustmentOut
    case reversal

    var title: String {
        switch self {
        case .income: return "درآمد"
        case .expense: return "هزینه"
        case .transfer: return "انتقال"
        case .settlementIn: return "دریافت بابت طلب/چک"
        case .settlementOut: return "پرداخت بابت بدهی/چک"
        case .adjustmentIn: return "تعدیل افزایشی موجودی"
        case .adjustmentOut: return "تعدیل کاهشی موجودی"
        case .reversal: return "برگشت"
        }
    }
}

enum ObligationDirection: String, Codable, CaseIterable, Sendable {
    /// Someone owes me (طلب).
    case receivable
    /// I owe someone (بدهی).
    case payable

    var title: String {
        switch self {
        case .receivable: return "طلب"
        case .payable: return "بدهی"
        }
    }
}

/// How sure the user is that an incoming amount will actually arrive on its date.
enum ReceiptConfidence: String, Codable, CaseIterable, Sendable {
    case confirmed
    case expected
    case uncertain

    var title: String {
        switch self {
        case .confirmed: return "قطعی"
        case .expected: return "احتمالاً"
        case .uncertain: return "نامطمئن"
        }
    }
}

enum ChequeDirection: String, Codable, CaseIterable, Sendable {
    case issued
    case received

    var title: String {
        switch self {
        case .issued: return "چک صادره"
        case .received: return "چک دریافتی"
        }
    }
}

/// Recorded (legal) lifecycle of a cheque. Settlement progress is derived from settlements,
/// and "due soon" / "overdue" are derived from today's date, so neither is stored twice.
enum ChequeLifecycle: String, Codable, CaseIterable, Sendable {
    case active
    case bounced
    case cancelled
    case returned
}

/// Status shown to the user.
enum ChequeStatus: String, Codable, CaseIterable, Sendable {
    case open
    case dueSoon
    case overdue
    case partiallySettled
    case settled
    case bounced
    case cancelled
    case returned

    var title: String {
        switch self {
        case .open: return "باز"
        case .dueSoon: return "نزدیک سررسید"
        case .overdue: return "سررسید گذشته"
        case .partiallySettled: return "تسویه جزئی"
        case .settled: return "تسویه‌شده"
        case .bounced: return "برگشتی"
        case .cancelled: return "باطل‌شده"
        case .returned: return "عودت‌شده"
        }
    }
}

enum SettlementMethod: String, Codable, CaseIterable, Sendable {
    /// Real money moved through an account.
    case cash
    /// Explicit offset (تهاتر) between a receivable and a payable of the same person.
    case offset
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var title: String {
        switch self {
        case .daily: return "روزانه"
        case .weekly: return "هفتگی"
        case .monthly: return "ماهانه"
        case .yearly: return "سالانه"
        }
    }
}

enum CashFlowDirection: String, Codable, Sendable {
    case inflow
    case outflow
}

struct AccountSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var kind: AccountKind
    var openingBalance: Money
    var isActive: Bool
    var sortOrder: Int
}

struct ContactSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var phone: String
    var note: String
}

struct CategorySnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var sortOrder: Int
    var isArchived: Bool
}

struct TransactionSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var kind: TransactionKind
    var amount: Money
    var date: CivilDate
    var fromAccountId: UUID?
    var toAccountId: UUID?
    var contactId: UUID?
    var categoryId: UUID?
    var note: String
    var reversesTransactionId: UUID?
    var recurrenceKey: String?
    var eventGroupId: UUID
    var chequeId: UUID?
    var obligationId: UUID?
    var createdAt: Date
}

struct ObligationSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var direction: ObligationDirection
    var contactId: UUID
    var principal: Money
    var dueDate: CivilDate?
    var createdOn: CivilDate
    var isCancelled: Bool
    var confidence: ReceiptConfidence
    var note: String
    var createdAt: Date
}

struct ChequeSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var direction: ChequeDirection
    var amount: Money
    var dueDate: CivilDate
    var contactId: UUID?
    var bankName: String
    var accountId: UUID?
    var chequeNumber: String
    var sayadId: String
    var lifecycle: ChequeLifecycle
    var obligationId: UUID?
    var confidence: ReceiptConfidence
    var note: String
    var createdAt: Date
}

struct SettlementSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var obligationId: UUID?
    var chequeId: UUID?
    var amount: Money
    var date: CivilDate
    var method: SettlementMethod
    var transactionId: UUID?
    var groupId: UUID
    var isVoided: Bool
}

struct RecurringRuleSnapshot: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    /// Only `.income` or `.expense`.
    var kind: TransactionKind
    var amount: Money
    var accountId: UUID?
    var categoryId: UUID?
    var startDate: CivilDate
    var endDate: CivilDate?
    var frequency: RecurrenceFrequency
    var interval: Int
    var monthEndPolicy: MonthEndPolicy
    var isActive: Bool
    var confidence: ReceiptConfidence
}

/// Everything the engines need, loaded once per refresh.
struct LedgerSnapshot: Sendable {
    var accounts: [AccountSnapshot] = []
    var contacts: [ContactSnapshot] = []
    var categories: [CategorySnapshot] = []
    var transactions: [TransactionSnapshot] = []
    var obligations: [ObligationSnapshot] = []
    var cheques: [ChequeSnapshot] = []
    var settlements: [SettlementSnapshot] = []
    var recurringRules: [RecurringRuleSnapshot] = []
    /// Optional monthly budget for variable (non-recurring) spending.
    var monthlyBudget: Money?

    func account(_ id: UUID?) -> AccountSnapshot? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func contact(_ id: UUID?) -> ContactSnapshot? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    func category(_ id: UUID?) -> CategorySnapshot? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func obligation(_ id: UUID?) -> ObligationSnapshot? {
        guard let id else { return nil }
        return obligations.first { $0.id == id }
    }

    func cheque(_ id: UUID?) -> ChequeSnapshot? {
        guard let id else { return nil }
        return cheques.first { $0.id == id }
    }

    func transaction(_ id: UUID?) -> TransactionSnapshot? {
        guard let id else { return nil }
        return transactions.first { $0.id == id }
    }
}
