import Foundation
import SwiftData

/// Versioned, self-describing backup payload (encrypted by `BackupCrypto` before it leaves the app).
struct BackupPayload: Codable {
    static let currentFormat = 1

    var format: Int = BackupPayload.currentFormat
    var schemaVersion: String = "1.0.0"
    var createdAt: Date
    var appVersion: String
    var preferences: AppPreferences?
    var accounts: [AccountRecord]
    var contacts: [ContactRecord]
    var categories: [CategoryRecord]
    var transactions: [TransactionRecord]
    var obligations: [ObligationRecord]
    var cheques: [ChequeRecord]
    var settlements: [SettlementRecord]
    var recurringRules: [RecurringRecord]
    var budgets: [BudgetRecord]
    var attachments: [AttachmentRecord]
    var auditEvents: [AuditRecord]

    struct AccountRecord: Codable { var id: UUID; var name: String; var kind: String; var openingBalance: Int64; var isActive: Bool; var sortOrder: Int; var createdAt: Date; var updatedAt: Date }
    struct ContactRecord: Codable { var id: UUID; var name: String; var phone: String; var note: String; var createdAt: Date; var updatedAt: Date }
    struct CategoryRecord: Codable { var id: UUID; var name: String; var symbol: String; var sortOrder: Int; var isArchived: Bool; var createdAt: Date; var updatedAt: Date }
    struct TransactionRecord: Codable {
        var id: UUID; var kind: String; var amount: Int64; var day: Int; var fromAccountId: UUID?; var toAccountId: UUID?
        var contactId: UUID?; var categoryId: UUID?; var note: String; var reversesTransactionId: UUID?; var recurrenceKey: String?
        var eventGroupId: UUID; var chequeId: UUID?; var obligationId: UUID?; var attachmentId: UUID?; var createdAt: Date; var updatedAt: Date
    }
    struct ObligationRecord: Codable {
        var id: UUID; var direction: String; var contactId: UUID; var principal: Int64; var dueDay: Int?; var createdDay: Int
        var isCancelled: Bool; var confidence: String; var note: String; var createdAt: Date; var updatedAt: Date
    }
    struct ChequeRecord: Codable {
        var id: UUID; var direction: String; var amount: Int64; var dueDay: Int; var contactId: UUID?; var bankName: String
        var accountId: UUID?; var chequeNumber: String; var sayadId: String; var lifecycle: String; var obligationId: UUID?
        var confidence: String; var note: String; var attachmentId: UUID?; var createdAt: Date; var updatedAt: Date
    }
    struct SettlementRecord: Codable {
        var id: UUID; var obligationId: UUID?; var chequeId: UUID?; var amount: Int64; var day: Int; var method: String
        var transactionId: UUID?; var groupId: UUID; var isVoided: Bool; var createdAt: Date; var updatedAt: Date
    }
    struct RecurringRecord: Codable {
        var id: UUID; var title: String; var kind: String; var amount: Int64; var accountId: UUID?; var categoryId: UUID?
        var startDay: Int; var endDay: Int?; var frequency: String; var interval: Int; var monthEndPolicy: String
        var isActive: Bool; var confidence: String; var createdAt: Date; var updatedAt: Date
    }
    struct BudgetRecord: Codable { var id: UUID; var categoryId: UUID?; var monthlyLimit: Int64; var createdAt: Date; var updatedAt: Date }
    struct AttachmentRecord: Codable { var id: UUID; var ownerId: UUID; var fileName: String; var data: Data?; var createdAt: Date; var updatedAt: Date }
    struct AuditRecord: Codable { var id: UUID; var timestamp: Date; var action: String; var entityType: String; var entityId: UUID?; var summary: String }

    var counts: [(String, Int)] {
        [
            ("حساب", accounts.count), ("طرف حساب", contacts.count), ("تراکنش", transactions.count),
            ("طلب/بدهی", obligations.count), ("چک", cheques.count), ("تسویه", settlements.count),
            ("قاعده تکرار", recurringRules.count), ("دسته", categories.count), ("پیوست", attachments.count)
        ]
    }
}

struct BackupPreview {
    let payload: BackupPayload
    var createdAt: Date { payload.createdAt }
    var counts: [(String, Int)] { payload.counts }
}

/// Builds, validates and restores encrypted backups.
@MainActor
final class BackupService {
    let service: LedgerService
    let attachmentStore: AttachmentStore?

    init(service: LedgerService, attachmentStore: AttachmentStore?) {
        self.service = service
        self.attachmentStore = attachmentStore
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    func makePayload(preferences: AppPreferences?, now: Date = Date()) throws -> BackupPayload {
        typealias P = BackupPayload
        let s = service
        let accounts: [P.AccountRecord] = try s.fetchAll(FinancialAccount.self).map { a in
            P.AccountRecord(id: a.id, name: a.name, kind: a.kindRaw, openingBalance: a.openingBalanceRials, isActive: a.isActive,
                            sortOrder: a.sortOrder, createdAt: a.createdAt, updatedAt: a.updatedAt)
        }
        let contacts: [P.ContactRecord] = try s.fetchAll(Contact.self).map { c in
            P.ContactRecord(id: c.id, name: c.name, phone: c.phone, note: c.note, createdAt: c.createdAt, updatedAt: c.updatedAt)
        }
        let categories: [P.CategoryRecord] = try s.fetchAll(ExpenseCategory.self).map { c in
            P.CategoryRecord(id: c.id, name: c.name, symbol: c.symbol, sortOrder: c.sortOrder, isArchived: c.isArchived,
                             createdAt: c.createdAt, updatedAt: c.updatedAt)
        }
        let transactions: [P.TransactionRecord] = try s.fetchAll(MoneyTransaction.self).map { t in
            P.TransactionRecord(id: t.id, kind: t.kindRaw, amount: t.amountRials, day: t.dayNumber, fromAccountId: t.fromAccountId,
                                toAccountId: t.toAccountId, contactId: t.contactId, categoryId: t.categoryId, note: t.note,
                                reversesTransactionId: t.reversesTransactionId, recurrenceKey: t.recurrenceKey,
                                eventGroupId: t.eventGroupId, chequeId: t.chequeId, obligationId: t.obligationId,
                                attachmentId: t.attachmentId, createdAt: t.createdAt, updatedAt: t.updatedAt)
        }
        let obligations: [P.ObligationRecord] = try s.fetchAll(Obligation.self).map { o in
            P.ObligationRecord(id: o.id, direction: o.directionRaw, contactId: o.contactId, principal: o.principalRials,
                               dueDay: o.dueDayNumber, createdDay: o.createdDayNumber, isCancelled: o.isCancelled,
                               confidence: o.confidenceRaw, note: o.note, createdAt: o.createdAt, updatedAt: o.updatedAt)
        }
        let cheques: [P.ChequeRecord] = try s.fetchAll(Cheque.self).map { c in
            P.ChequeRecord(id: c.id, direction: c.directionRaw, amount: c.amountRials, dueDay: c.dueDayNumber,
                           contactId: c.contactId, bankName: c.bankName, accountId: c.accountId, chequeNumber: c.chequeNumber,
                           sayadId: c.sayadId, lifecycle: c.lifecycleRaw, obligationId: c.obligationId,
                           confidence: c.confidenceRaw, note: c.note, attachmentId: c.attachmentId,
                           createdAt: c.createdAt, updatedAt: c.updatedAt)
        }
        let settlements: [P.SettlementRecord] = try s.fetchAll(Settlement.self).map { x in
            P.SettlementRecord(id: x.id, obligationId: x.obligationId, chequeId: x.chequeId, amount: x.amountRials, day: x.dayNumber,
                               method: x.methodRaw, transactionId: x.transactionId, groupId: x.groupId, isVoided: x.isVoided,
                               createdAt: x.createdAt, updatedAt: x.updatedAt)
        }
        let rules: [P.RecurringRecord] = try s.fetchAll(RecurringRule.self).map { r in
            P.RecurringRecord(id: r.id, title: r.title, kind: r.kindRaw, amount: r.amountRials, accountId: r.accountId,
                              categoryId: r.categoryId, startDay: r.startDayNumber, endDay: r.endDayNumber,
                              frequency: r.frequencyRaw, interval: r.interval, monthEndPolicy: r.monthEndPolicyRaw,
                              isActive: r.isActive, confidence: r.confidenceRaw, createdAt: r.createdAt, updatedAt: r.updatedAt)
        }
        let budgets: [P.BudgetRecord] = try s.fetchAll(Budget.self).map { b in
            P.BudgetRecord(id: b.id, categoryId: b.categoryId, monthlyLimit: b.monthlyLimitRials, createdAt: b.createdAt, updatedAt: b.updatedAt)
        }
        let store = attachmentStore
        let attachments: [P.AttachmentRecord] = try s.fetchAll(Attachment.self).map { a in
            let data: Data? = try? store?.load(fileName: a.fileName)
            return P.AttachmentRecord(id: a.id, ownerId: a.ownerId, fileName: a.fileName, data: data,
                                      createdAt: a.createdAt, updatedAt: a.updatedAt)
        }
        let audit: [P.AuditRecord] = try s.fetchAll(AuditEvent.self).map { e in
            P.AuditRecord(id: e.id, timestamp: e.timestamp, action: e.action, entityType: e.entityType, entityId: e.entityId, summary: e.summary)
        }
        return BackupPayload(
            createdAt: now, appVersion: Self.appVersion, preferences: preferences,
            accounts: accounts, contacts: contacts, categories: categories, transactions: transactions,
            obligations: obligations, cheques: cheques, settlements: settlements, recurringRules: rules,
            budgets: budgets, attachments: attachments, auditEvents: audit
        )
    }

    static func encode(_ payload: BackupPayload) throws -> Data {
        // Default date strategy (seconds as Double) round-trips exactly; ISO-8601 would drop sub-second precision.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        struct Header: Decodable { var format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw DomainError.backupCorrupted }
        guard header.format <= BackupPayload.currentFormat else { throw DomainError.backupUnsupportedVersion(header.format) }
        do {
            return try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw DomainError.backupCorrupted
        }
    }

    func exportEncrypted(password: String, preferences: AppPreferences?, iterations: UInt32 = BackupCrypto.defaultIterations) throws -> Data {
        guard password.count >= BackupCrypto.minimumPasswordLength else { throw DomainError.passwordTooShort }
        let payload = try makePayload(preferences: preferences)
        return try BackupCrypto.encrypt(try Self.encode(payload), password: password, iterations: iterations)
    }

    /// Decrypts and fully validates a backup without touching the database.
    func inspect(_ data: Data, password: String) throws -> BackupPreview {
        let plain = try BackupCrypto.decrypt(data, password: password)
        let payload = try Self.decode(plain)
        try Self.validate(payload)
        return BackupPreview(payload: payload)
    }

    /// Integrity checks: unique ids, known enum values, references that resolve, and no over-settlement.
    static func validate(_ p: BackupPayload) throws {
        func unique(_ ids: [UUID], _ what: String) throws {
            guard Set(ids).count == ids.count else { throw DomainError.backupInvalid("شناسه تکراری در \(what)") }
        }
        try unique(p.accounts.map(\.id), "حساب‌ها")
        try unique(p.contacts.map(\.id), "طرف حساب‌ها")
        try unique(p.transactions.map(\.id), "تراکنش‌ها")
        try unique(p.obligations.map(\.id), "تعهدها")
        try unique(p.cheques.map(\.id), "چک‌ها")
        try unique(p.settlements.map(\.id), "تسویه‌ها")
        try unique(p.categories.map(\.id), "دسته‌ها")
        try unique(p.recurringRules.map(\.id), "قاعده‌ها")

        let accountIds = Set(p.accounts.map(\.id))
        let contactIds = Set(p.contacts.map(\.id))
        let obligationIds = Set(p.obligations.map(\.id))
        let chequeIds = Set(p.cheques.map(\.id))
        let txIds = Set(p.transactions.map(\.id))

        for a in p.accounts where AccountKind(rawValue: a.kind) == nil { throw DomainError.backupInvalid("نوع حساب نامعتبر") }
        for t in p.transactions {
            guard TransactionKind(rawValue: t.kind) != nil, t.amount > 0 else { throw DomainError.backupInvalid("تراکنش نامعتبر") }
            for ref in [t.fromAccountId, t.toAccountId].compactMap({ $0 }) where !accountIds.contains(ref) {
                throw DomainError.backupInvalid("تراکنش به حساب ناموجود اشاره می‌کند")
            }
            if let r = t.reversesTransactionId, !txIds.contains(r) { throw DomainError.backupInvalid("برگشتِ بدون تراکنش اصلی") }
        }
        for o in p.obligations {
            guard ObligationDirection(rawValue: o.direction) != nil, o.principal > 0 else { throw DomainError.backupInvalid("طلب/بدهی نامعتبر") }
            guard contactIds.contains(o.contactId) else { throw DomainError.backupInvalid("طلب/بدهی بدون طرف حساب") }
        }
        for c in p.cheques {
            guard ChequeDirection(rawValue: c.direction) != nil, ChequeLifecycle(rawValue: c.lifecycle) != nil, c.amount > 0 else {
                throw DomainError.backupInvalid("چک نامعتبر")
            }
            if let o = c.obligationId, !obligationIds.contains(o) { throw DomainError.backupInvalid("چک به تعهد ناموجود اشاره می‌کند") }
        }
        var settledByObligation: [UUID: Int64] = [:]
        var settledByCheque: [UUID: Int64] = [:]
        for s in p.settlements {
            guard s.amount > 0, SettlementMethod(rawValue: s.method) != nil else { throw DomainError.backupInvalid("تسویه نامعتبر") }
            if let o = s.obligationId {
                guard obligationIds.contains(o) else { throw DomainError.backupInvalid("تسویه بدون تعهد") }
                if !s.isVoided { settledByObligation[o, default: 0] += s.amount }
            }
            if let c = s.chequeId {
                guard chequeIds.contains(c) else { throw DomainError.backupInvalid("تسویه بدون چک") }
                if !s.isVoided { settledByCheque[c, default: 0] += s.amount }
            }
            if let t = s.transactionId, !txIds.contains(t) { throw DomainError.backupInvalid("تسویه بدون تراکنش") }
        }
        for o in p.obligations where (settledByObligation[o.id] ?? 0) > o.principal {
            throw DomainError.backupInvalid("تسویه بیش از مبلغ تعهد")
        }
        for c in p.cheques where (settledByCheque[c.id] ?? 0) > c.amount {
            throw DomainError.backupInvalid("تسویه بیش از مبلغ چک")
        }
    }

    /// Replaces all data with the backup in ONE save. If anything fails, the context is rolled back
    /// and the existing database stays exactly as it was.
    func restore(_ preview: BackupPreview) throws {
        let p = preview.payload
        try Self.validate(p)
        let context = service.context
        var writtenFiles: [String] = []
        do {
            try service.deleteEverything()
            for a in p.accounts {
                let m = FinancialAccount(id: a.id, name: a.name, kind: AccountKind(rawValue: a.kind) ?? .bank,
                                         openingBalance: Money(rials: a.openingBalance), sortOrder: a.sortOrder, now: a.createdAt)
                m.isActive = a.isActive
                m.updatedAt = a.updatedAt
                context.insert(m)
            }
            for c in p.contacts {
                let m = Contact(id: c.id, name: c.name, phone: c.phone, note: c.note, now: c.createdAt)
                m.updatedAt = c.updatedAt
                context.insert(m)
            }
            for c in p.categories {
                let m = ExpenseCategory(id: c.id, name: c.name, symbol: c.symbol, sortOrder: c.sortOrder, now: c.createdAt)
                m.isArchived = c.isArchived
                m.updatedAt = c.updatedAt
                context.insert(m)
            }
            for t in p.transactions {
                let m = MoneyTransaction(
                    id: t.id, kind: TransactionKind(rawValue: t.kind) ?? .expense, amount: Money(rials: t.amount),
                    date: CivilDate(dayNumber: t.day), fromAccountId: t.fromAccountId, toAccountId: t.toAccountId,
                    contactId: t.contactId, categoryId: t.categoryId, note: t.note,
                    reversesTransactionId: t.reversesTransactionId, recurrenceKey: t.recurrenceKey,
                    eventGroupId: t.eventGroupId, chequeId: t.chequeId, obligationId: t.obligationId, now: t.createdAt
                )
                m.attachmentId = t.attachmentId
                m.updatedAt = t.updatedAt
                context.insert(m)
            }
            for o in p.obligations {
                let m = Obligation(
                    id: o.id, direction: ObligationDirection(rawValue: o.direction) ?? .payable, contactId: o.contactId,
                    principal: Money(rials: o.principal), dueDate: o.dueDay.map(CivilDate.init(dayNumber:)),
                    createdOn: CivilDate(dayNumber: o.createdDay),
                    confidence: ReceiptConfidence(rawValue: o.confidence) ?? .expected, note: o.note, now: o.createdAt
                )
                m.isCancelled = o.isCancelled
                m.updatedAt = o.updatedAt
                context.insert(m)
            }
            for c in p.cheques {
                let m = Cheque(
                    id: c.id, direction: ChequeDirection(rawValue: c.direction) ?? .issued, amount: Money(rials: c.amount),
                    dueDate: CivilDate(dayNumber: c.dueDay), contactId: c.contactId, bankName: c.bankName,
                    accountId: c.accountId, chequeNumber: c.chequeNumber, sayadId: c.sayadId, obligationId: c.obligationId,
                    confidence: ReceiptConfidence(rawValue: c.confidence) ?? .expected, note: c.note, now: c.createdAt
                )
                m.lifecycleRaw = c.lifecycle
                m.attachmentId = c.attachmentId
                m.updatedAt = c.updatedAt
                context.insert(m)
            }
            for s in p.settlements {
                let m = Settlement(
                    id: s.id, obligationId: s.obligationId, chequeId: s.chequeId, amount: Money(rials: s.amount),
                    date: CivilDate(dayNumber: s.day), method: SettlementMethod(rawValue: s.method) ?? .cash,
                    transactionId: s.transactionId, groupId: s.groupId, now: s.createdAt
                )
                m.isVoided = s.isVoided
                m.updatedAt = s.updatedAt
                context.insert(m)
            }
            for r in p.recurringRules {
                let m = RecurringRule(
                    id: r.id, title: r.title, kind: TransactionKind(rawValue: r.kind) ?? .expense, amount: Money(rials: r.amount),
                    accountId: r.accountId, categoryId: r.categoryId, startDate: CivilDate(dayNumber: r.startDay),
                    endDate: r.endDay.map(CivilDate.init(dayNumber:)),
                    frequency: RecurrenceFrequency(rawValue: r.frequency) ?? .monthly, interval: r.interval,
                    monthEndPolicy: MonthEndPolicy(rawValue: r.monthEndPolicy) ?? .lastValidDay,
                    confidence: ReceiptConfidence(rawValue: r.confidence) ?? .confirmed, now: r.createdAt
                )
                m.isActive = r.isActive
                m.updatedAt = r.updatedAt
                context.insert(m)
            }
            for b in p.budgets {
                let m = Budget(id: b.id, categoryId: b.categoryId, monthlyLimit: Money(rials: b.monthlyLimit), now: b.createdAt)
                m.updatedAt = b.updatedAt
                context.insert(m)
            }
            for a in p.attachments {
                if let data = a.data, let store = attachmentStore {
                    try store.save(data, fileName: a.fileName)
                    writtenFiles.append(a.fileName)
                }
                let m = Attachment(id: a.id, ownerId: a.ownerId, fileName: a.fileName, now: a.createdAt)
                m.updatedAt = a.updatedAt
                context.insert(m)
            }
            for e in p.auditEvents {
                let m = AuditEvent(id: e.id, action: e.action, entityType: e.entityType, entityId: e.entityId, summary: e.summary, now: e.timestamp)
                context.insert(m)
            }
            context.insert(AuditEvent(action: "restore", entityType: "backup", entityId: nil, summary: "بازیابی از پشتیبان"))
            try context.save()
        } catch {
            context.rollback()
            // Files written for the failed restore are not referenced by the old data; best-effort cleanup.
            let existing = Set((try? service.attachments().map(\.fileName)) ?? [])
            for name in writtenFiles where !existing.contains(name) {
                attachmentStore?.delete(fileName: name)
            }
            throw error
        }
    }
}
