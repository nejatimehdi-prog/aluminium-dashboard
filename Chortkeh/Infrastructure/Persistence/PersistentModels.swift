import Foundation
import SwiftData

// SwiftData models. References between records are plain UUIDs (no @Relationship), so nothing is ever
// cascade-deleted behind the user's back and backups are a straightforward copy.
// Enums are stored as raw strings; amounts as Int64 rials; calendar days as Julian Day Numbers.
// `id` values are random UUIDs; uniqueness is also validated on restore. No `.unique` attribute is used so that
// a restore (delete all + insert in one save) never triggers SwiftData's implicit upsert behaviour.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            FinancialAccount.self, Contact.self, MoneyTransaction.self, Obligation.self, Cheque.self,
            Settlement.self, RecurringRule.self, Budget.self, ExpenseCategory.self, Attachment.self, AuditEvent.self
        ]
    }

    @Model
    final class FinancialAccount {
        var id: UUID
        var name: String
        var kindRaw: String
        var openingBalanceRials: Int64
        var isActive: Bool
        var sortOrder: Int
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, kind: AccountKind, openingBalance: Money, sortOrder: Int, now: Date = Date()) {
            self.id = id
            self.name = name
            self.kindRaw = kind.rawValue
            self.openingBalanceRials = openingBalance.rials
            self.isActive = true
            self.sortOrder = sortOrder
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Contact {
        var id: UUID
        var name: String
        var phone: String
        var note: String
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, phone: String = "", note: String = "", now: Date = Date()) {
            self.id = id
            self.name = name
            self.phone = phone
            self.note = note
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class MoneyTransaction {
        var id: UUID
        var kindRaw: String
        var amountRials: Int64
        var dayNumber: Int
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
        var attachmentId: UUID?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), kind: TransactionKind, amount: Money, date: CivilDate,
            fromAccountId: UUID? = nil, toAccountId: UUID? = nil, contactId: UUID? = nil, categoryId: UUID? = nil,
            note: String = "", reversesTransactionId: UUID? = nil, recurrenceKey: String? = nil,
            eventGroupId: UUID = UUID(), chequeId: UUID? = nil, obligationId: UUID? = nil, now: Date = Date()
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.amountRials = amount.rials
            self.dayNumber = date.dayNumber
            self.fromAccountId = fromAccountId
            self.toAccountId = toAccountId
            self.contactId = contactId
            self.categoryId = categoryId
            self.note = note
            self.reversesTransactionId = reversesTransactionId
            self.recurrenceKey = recurrenceKey
            self.eventGroupId = eventGroupId
            self.chequeId = chequeId
            self.obligationId = obligationId
            self.attachmentId = nil
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Obligation {
        var id: UUID
        var directionRaw: String
        var contactId: UUID
        var principalRials: Int64
        var dueDayNumber: Int?
        var createdDayNumber: Int
        var isCancelled: Bool
        var confidenceRaw: String
        var note: String
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), direction: ObligationDirection, contactId: UUID, principal: Money,
            dueDate: CivilDate?, createdOn: CivilDate, confidence: ReceiptConfidence, note: String, now: Date = Date()
        ) {
            self.id = id
            self.directionRaw = direction.rawValue
            self.contactId = contactId
            self.principalRials = principal.rials
            self.dueDayNumber = dueDate?.dayNumber
            self.createdDayNumber = createdOn.dayNumber
            self.isCancelled = false
            self.confidenceRaw = confidence.rawValue
            self.note = note
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Cheque {
        var id: UUID
        var directionRaw: String
        var amountRials: Int64
        var dueDayNumber: Int
        var contactId: UUID?
        var bankName: String
        var accountId: UUID?
        var chequeNumber: String
        var sayadId: String
        var lifecycleRaw: String
        var obligationId: UUID?
        var confidenceRaw: String
        var note: String
        var attachmentId: UUID?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), direction: ChequeDirection, amount: Money, dueDate: CivilDate, contactId: UUID?,
            bankName: String = "", accountId: UUID? = nil, chequeNumber: String = "", sayadId: String = "",
            obligationId: UUID? = nil, confidence: ReceiptConfidence = .expected, note: String = "", now: Date = Date()
        ) {
            self.id = id
            self.directionRaw = direction.rawValue
            self.amountRials = amount.rials
            self.dueDayNumber = dueDate.dayNumber
            self.contactId = contactId
            self.bankName = bankName
            self.accountId = accountId
            self.chequeNumber = chequeNumber
            self.sayadId = sayadId
            self.lifecycleRaw = ChequeLifecycle.active.rawValue
            self.obligationId = obligationId
            self.confidenceRaw = confidence.rawValue
            self.note = note
            self.attachmentId = nil
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Settlement {
        var id: UUID
        var obligationId: UUID?
        var chequeId: UUID?
        var amountRials: Int64
        var dayNumber: Int
        var methodRaw: String
        var transactionId: UUID?
        var groupId: UUID
        var isVoided: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), obligationId: UUID? = nil, chequeId: UUID? = nil, amount: Money, date: CivilDate,
            method: SettlementMethod, transactionId: UUID?, groupId: UUID, now: Date = Date()
        ) {
            self.id = id
            self.obligationId = obligationId
            self.chequeId = chequeId
            self.amountRials = amount.rials
            self.dayNumber = date.dayNumber
            self.methodRaw = method.rawValue
            self.transactionId = transactionId
            self.groupId = groupId
            self.isVoided = false
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class RecurringRule {
        var id: UUID
        var title: String
        var kindRaw: String
        var amountRials: Int64
        var accountId: UUID?
        var categoryId: UUID?
        var startDayNumber: Int
        var endDayNumber: Int?
        var frequencyRaw: String
        var interval: Int
        var monthEndPolicyRaw: String
        var isActive: Bool
        var confidenceRaw: String
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), title: String, kind: TransactionKind, amount: Money, accountId: UUID?, categoryId: UUID?,
            startDate: CivilDate, endDate: CivilDate?, frequency: RecurrenceFrequency, interval: Int,
            monthEndPolicy: MonthEndPolicy, confidence: ReceiptConfidence = .confirmed, now: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.kindRaw = kind.rawValue
            self.amountRials = amount.rials
            self.accountId = accountId
            self.categoryId = categoryId
            self.startDayNumber = startDate.dayNumber
            self.endDayNumber = endDate?.dayNumber
            self.frequencyRaw = frequency.rawValue
            self.interval = interval
            self.monthEndPolicyRaw = monthEndPolicy.rawValue
            self.isActive = true
            self.confidenceRaw = confidence.rawValue
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Budget {
        var id: UUID
        /// nil = overall monthly budget for variable spending.
        var categoryId: UUID?
        var monthlyLimitRials: Int64
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), categoryId: UUID? = nil, monthlyLimit: Money, now: Date = Date()) {
            self.id = id
            self.categoryId = categoryId
            self.monthlyLimitRials = monthlyLimit.rials
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class ExpenseCategory {
        var id: UUID
        var name: String
        var symbol: String
        var sortOrder: Int
        var isArchived: Bool
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), name: String, symbol: String, sortOrder: Int, now: Date = Date()) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.sortOrder = sortOrder
            self.isArchived = false
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class Attachment {
        var id: UUID
        var ownerId: UUID
        /// File name inside the encrypted attachments directory.
        var fileName: String
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), ownerId: UUID, fileName: String, now: Date = Date()) {
            self.id = id
            self.ownerId = ownerId
            self.fileName = fileName
            self.createdAt = now
            self.updatedAt = now
        }
    }

    /// Local, append-only audit trail of financial operations.
    @Model
    final class AuditEvent {
        var id: UUID
        var timestamp: Date
        var action: String
        var entityType: String
        var entityId: UUID?
        var summary: String
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), action: String, entityType: String, entityId: UUID?, summary: String, now: Date = Date()) {
            self.id = id
            self.timestamp = now
            self.action = action
            self.entityType = entityType
            self.entityId = entityId
            self.summary = summary
            self.createdAt = now
            self.updatedAt = now
        }
    }
}

typealias FinancialAccount = SchemaV1.FinancialAccount
typealias Contact = SchemaV1.Contact
typealias MoneyTransaction = SchemaV1.MoneyTransaction
typealias Obligation = SchemaV1.Obligation
typealias Cheque = SchemaV1.Cheque
typealias Settlement = SchemaV1.Settlement
typealias RecurringRule = SchemaV1.RecurringRule
typealias Budget = SchemaV1.Budget
typealias ExpenseCategory = SchemaV1.ExpenseCategory
typealias Attachment = SchemaV1.Attachment
typealias AuditEvent = SchemaV1.AuditEvent

enum ChortkehMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Snapshot mapping

extension SchemaV1.FinancialAccount {
    var snapshot: AccountSnapshot {
        AccountSnapshot(
            id: id, name: name, kind: AccountKind(rawValue: kindRaw) ?? .bank,
            openingBalance: Money(rials: openingBalanceRials), isActive: isActive, sortOrder: sortOrder
        )
    }
}

extension SchemaV1.Contact {
    var snapshot: ContactSnapshot { ContactSnapshot(id: id, name: name, phone: phone, note: note) }
}

extension SchemaV1.ExpenseCategory {
    var snapshot: CategorySnapshot {
        CategorySnapshot(id: id, name: name, symbol: symbol, sortOrder: sortOrder, isArchived: isArchived)
    }
}

extension SchemaV1.MoneyTransaction {
    var snapshot: TransactionSnapshot {
        TransactionSnapshot(
            id: id, kind: TransactionKind(rawValue: kindRaw) ?? .expense, amount: Money(rials: amountRials),
            date: CivilDate(dayNumber: dayNumber), fromAccountId: fromAccountId, toAccountId: toAccountId,
            contactId: contactId, categoryId: categoryId, note: note, reversesTransactionId: reversesTransactionId,
            recurrenceKey: recurrenceKey, eventGroupId: eventGroupId, chequeId: chequeId, obligationId: obligationId,
            createdAt: createdAt
        )
    }
}

extension SchemaV1.Obligation {
    var snapshot: ObligationSnapshot {
        ObligationSnapshot(
            id: id, direction: ObligationDirection(rawValue: directionRaw) ?? .payable, contactId: contactId,
            principal: Money(rials: principalRials), dueDate: dueDayNumber.map(CivilDate.init(dayNumber:)),
            createdOn: CivilDate(dayNumber: createdDayNumber), isCancelled: isCancelled,
            confidence: ReceiptConfidence(rawValue: confidenceRaw) ?? .expected, note: note, createdAt: createdAt
        )
    }
}

extension SchemaV1.Cheque {
    var snapshot: ChequeSnapshot {
        ChequeSnapshot(
            id: id, direction: ChequeDirection(rawValue: directionRaw) ?? .issued, amount: Money(rials: amountRials),
            dueDate: CivilDate(dayNumber: dueDayNumber), contactId: contactId, bankName: bankName, accountId: accountId,
            chequeNumber: chequeNumber, sayadId: sayadId, lifecycle: ChequeLifecycle(rawValue: lifecycleRaw) ?? .active,
            obligationId: obligationId, confidence: ReceiptConfidence(rawValue: confidenceRaw) ?? .expected,
            note: note, createdAt: createdAt
        )
    }
}

extension SchemaV1.Settlement {
    var snapshot: SettlementSnapshot {
        SettlementSnapshot(
            id: id, obligationId: obligationId, chequeId: chequeId, amount: Money(rials: amountRials),
            date: CivilDate(dayNumber: dayNumber), method: SettlementMethod(rawValue: methodRaw) ?? .cash,
            transactionId: transactionId, groupId: groupId, isVoided: isVoided
        )
    }
}

extension SchemaV1.RecurringRule {
    var snapshot: RecurringRuleSnapshot {
        RecurringRuleSnapshot(
            id: id, title: title, kind: TransactionKind(rawValue: kindRaw) ?? .expense, amount: Money(rials: amountRials),
            accountId: accountId, categoryId: categoryId, startDate: CivilDate(dayNumber: startDayNumber),
            endDate: endDayNumber.map(CivilDate.init(dayNumber:)),
            frequency: RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly, interval: max(1, interval),
            monthEndPolicy: MonthEndPolicy(rawValue: monthEndPolicyRaw) ?? .lastValidDay, isActive: isActive,
            confidence: ReceiptConfidence(rawValue: confidenceRaw) ?? .confirmed
        )
    }
}
