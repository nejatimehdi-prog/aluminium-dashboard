import Foundation
import SwiftData

/// All write operations. Each public method validates against the current ledger, applies its changes
/// and saves once; on any error every change of that call is rolled back (atomic per operation).
@MainActor
final class LedgerService {
    let context: ModelContext
    private let clock: () -> Date
    private let timeZone: TimeZone

    init(context: ModelContext, clock: @escaping () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.context = context
        self.context.autosaveEnabled = false
        self.clock = clock
        self.timeZone = timeZone
    }

    var now: Date { clock() }
    var today: CivilDate { CivilDate.from(clock(), timeZone: timeZone) }

    // MARK: - Reading

    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    func loadSnapshot() throws -> LedgerSnapshot {
        var s = LedgerSnapshot()
        s.accounts = try fetchAll(FinancialAccount.self).map(\.snapshot)
        s.contacts = try fetchAll(Contact.self).map(\.snapshot).sorted { $0.name < $1.name }
        s.categories = try fetchAll(ExpenseCategory.self).map(\.snapshot).sorted { $0.sortOrder < $1.sortOrder }
        s.transactions = try fetchAll(MoneyTransaction.self).map(\.snapshot)
        s.obligations = try fetchAll(Obligation.self).map(\.snapshot)
        s.cheques = try fetchAll(Cheque.self).map(\.snapshot)
        s.settlements = try fetchAll(Settlement.self).map(\.snapshot)
        s.recurringRules = try fetchAll(RecurringRule.self).map(\.snapshot)
        let budget = try fetchAll(Budget.self).first { $0.categoryId == nil }
        s.monthlyBudget = budget.map { Money(rials: $0.monthlyLimitRials) }
        return s
    }

    private func find<T: PersistentModel>(_ type: T.Type, _ predicate: (T) -> Bool) throws -> T {
        guard let item = try fetchAll(type).first(where: predicate) else { throw DomainError.notFound }
        return item
    }

    func account(_ id: UUID) throws -> FinancialAccount { try find(FinancialAccount.self) { $0.id == id } }
    func contact(_ id: UUID) throws -> Contact { try find(Contact.self) { $0.id == id } }
    func obligation(_ id: UUID) throws -> Obligation { try find(Obligation.self) { $0.id == id } }
    func cheque(_ id: UUID) throws -> Cheque { try find(Cheque.self) { $0.id == id } }
    func transaction(_ id: UUID) throws -> MoneyTransaction { try find(MoneyTransaction.self) { $0.id == id } }

    // MARK: - Atomic helper

    @discardableResult
    private func atomic<R>(_ action: String, _ body: () throws -> R) throws -> R {
        do {
            let result = try body()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private func audit(_ action: String, _ entityType: String, _ id: UUID?, _ summary: String) {
        context.insert(AuditEvent(action: action, entityType: entityType, entityId: id, summary: summary, now: now))
    }

    // MARK: - Setup

    static let defaultCategories: [(String, String)] = [
        ("خانه", "house"), ("خرید روزانه", "cart"), ("خوراک", "fork.knife"), ("خودرو و سوخت", "car"),
        ("خانواده و آموزش", "figure.2.and.child.holdinghands"), ("درمان", "cross.case"), ("تفریح", "gamecontroller"),
        ("سفر", "airplane"), ("سایر", "ellipsis.circle")
    ]

    func seedDefaultCategoriesIfNeeded() throws {
        guard try fetchAll(ExpenseCategory.self).isEmpty else { return }
        try atomic("seed") {
            for (index, item) in Self.defaultCategories.enumerated() {
                context.insert(ExpenseCategory(name: item.0, symbol: item.1, sortOrder: index, now: now))
            }
        }
    }

    // MARK: - Accounts

    @discardableResult
    func addAccount(name: String, kind: AccountKind, openingBalance: Money) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        guard openingBalance.rials.magnitude <= UInt64(Money.maxInputRials) else { throw DomainError.amountOutOfRange }
        return try atomic("addAccount") {
            let order = try fetchAll(FinancialAccount.self).count
            let account = FinancialAccount(name: trimmed, kind: kind, openingBalance: openingBalance, sortOrder: order, now: now)
            context.insert(account)
            audit("create", "account", account.id, "ایجاد حساب")
            return account.id
        }
    }

    func renameAccount(_ id: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        try atomic("renameAccount") {
            let a = try account(id)
            a.name = trimmed
            a.updatedAt = now
        }
    }

    func setAccountActive(_ id: UUID, active: Bool) throws {
        try atomic("setAccountActive") {
            let a = try account(id)
            a.isActive = active
            a.updatedAt = now
            audit(active ? "activate" : "deactivate", "account", id, active ? "فعال‌سازی حساب" : "غیرفعال‌سازی حساب")
        }
    }

    /// Opening balance is changed only before the account has any transaction; afterwards use `adjustBalance`.
    func setOpeningBalance(_ id: UUID, amount: Money) throws {
        let ledger = try loadSnapshot()
        guard !ledger.transactions.contains(where: { $0.fromAccountId == id || $0.toAccountId == id }) else {
            throw DomainError.hasDependencies("تراکنش (برای اصلاح از «تعدیل موجودی» استفاده کن)")
        }
        try atomic("setOpeningBalance") {
            let a = try account(id)
            a.openingBalanceRials = amount.rials
            a.updatedAt = now
            audit("update", "account", id, "اصلاح موجودی اولیه")
        }
    }

    /// Brings the recorded balance to `actual` with a visible adjustment transaction.
    @discardableResult
    func adjustBalance(accountId: UUID, actual: Money, date: CivilDate, note: String = "") throws -> UUID? {
        let ledger = try loadSnapshot()
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        let current = try FinancialCalculator.balance(of: accountId, in: ledger)
        let diff = try actual - current
        guard !diff.isZero else { return nil }
        return try atomic("adjust") {
            let isIn = diff.isPositive
            let tx = MoneyTransaction(
                kind: isIn ? .adjustmentIn : .adjustmentOut,
                amount: try diff.abs(),
                date: date,
                fromAccountId: isIn ? nil : accountId,
                toAccountId: isIn ? accountId : nil,
                note: note.isEmpty ? "تعدیل موجودی" : note,
                now: now
            )
            context.insert(tx)
            audit("adjust", "transaction", tx.id, "تعدیل موجودی حساب")
            return tx.id
        }
    }

    func deleteAccount(_ id: UUID) throws {
        let deps = LedgerRules.dependencies(ofAccount: id, in: try loadSnapshot())
        guard deps.isEmpty else { throw DomainError.hasDependencies(deps.joined(separator: "، ")) }
        try atomic("deleteAccount") {
            context.delete(try account(id))
            audit("delete", "account", id, "حذف حساب بدون تراکنش")
        }
    }

    // MARK: - Contacts & categories

    @discardableResult
    func addContact(name: String, phone: String = "", note: String = "") throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        return try atomic("addContact") {
            let c = Contact(name: trimmed, phone: phone, note: note, now: now)
            context.insert(c)
            return c.id
        }
    }

    /// Finds a contact by exact name or creates it.
    func contactId(named name: String) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.contactRequired }
        if let existing = try fetchAll(Contact.self).first(where: { $0.name == trimmed }) { return existing.id }
        return try addContact(name: trimmed)
    }

    func updateContact(_ id: UUID, name: String, phone: String, note: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        try atomic("updateContact") {
            let c = try contact(id)
            c.name = trimmed
            c.phone = phone
            c.note = note
            c.updatedAt = now
        }
    }

    func deleteContact(_ id: UUID) throws {
        let deps = LedgerRules.dependencies(ofContact: id, in: try loadSnapshot())
        guard deps.isEmpty else { throw DomainError.hasDependencies(deps.joined(separator: "، ")) }
        try atomic("deleteContact") { context.delete(try contact(id)) }
    }

    @discardableResult
    func addCategory(name: String, symbol: String = "tag") throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        return try atomic("addCategory") {
            let order = try fetchAll(ExpenseCategory.self).count
            let c = ExpenseCategory(name: trimmed, symbol: symbol, sortOrder: order, now: now)
            context.insert(c)
            return c.id
        }
    }

    func updateCategory(_ id: UUID, name: String, archived: Bool) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        try atomic("updateCategory") {
            let c = try find(ExpenseCategory.self) { $0.id == id }
            c.name = trimmed
            c.isArchived = archived
            c.updatedAt = now
        }
    }

    func setMonthlyBudget(_ amount: Money?) throws {
        try atomic("budget") {
            let existing = try fetchAll(Budget.self).filter { $0.categoryId == nil }
            if let amount, amount.isPositive {
                if let b = existing.first {
                    b.monthlyLimitRials = amount.rials
                    b.updatedAt = now
                } else {
                    context.insert(Budget(monthlyLimit: amount, now: now))
                }
            } else {
                existing.forEach { context.delete($0) }
            }
        }
    }

    // MARK: - Income / expense / transfer

    @discardableResult
    func recordExpense(amount: Money, accountId: UUID?, date: CivilDate, categoryId: UUID? = nil,
                       contactId: UUID? = nil, note: String = "", recurrenceKey: String? = nil) throws -> UUID {
        let ledger = try loadSnapshot()
        try LedgerRules.requirePositive(amount)
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        return try atomic("expense") {
            let tx = MoneyTransaction(kind: .expense, amount: amount, date: date, fromAccountId: accountId,
                                      contactId: contactId, categoryId: categoryId, note: note,
                                      recurrenceKey: recurrenceKey, now: now)
            context.insert(tx)
            return tx.id
        }
    }

    @discardableResult
    func recordIncome(amount: Money, accountId: UUID?, date: CivilDate, categoryId: UUID? = nil,
                      contactId: UUID? = nil, note: String = "", recurrenceKey: String? = nil) throws -> UUID {
        let ledger = try loadSnapshot()
        try LedgerRules.requirePositive(amount)
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        return try atomic("income") {
            let tx = MoneyTransaction(kind: .income, amount: amount, date: date, toAccountId: accountId,
                                      contactId: contactId, categoryId: categoryId, note: note,
                                      recurrenceKey: recurrenceKey, now: now)
            context.insert(tx)
            return tx.id
        }
    }

    /// One balanced transaction: total cash is unchanged.
    @discardableResult
    func transfer(amount: Money, from: UUID?, to: UUID?, date: CivilDate, note: String = "") throws -> UUID {
        try LedgerRules.validateTransfer(amount: amount, from: from, to: to, in: try loadSnapshot())
        return try atomic("transfer") {
            let tx = MoneyTransaction(kind: .transfer, amount: amount, date: date, fromAccountId: from, toAccountId: to,
                                      note: note, now: now)
            context.insert(tx)
            return tx.id
        }
    }

    /// Reverses a transaction with an opposite, linked transaction (never a silent delete).
    /// Settlements paid by that transaction are voided so the related debt/cheque re-opens.
    @discardableResult
    func reverseTransaction(_ id: UUID, date: CivilDate? = nil, reason: String = "") throws -> UUID {
        let ledger = try loadSnapshot()
        let original = try LedgerRules.validateReversal(transactionId: id, in: ledger)
        return try atomic("reverse") {
            let rev = MoneyTransaction(
                kind: .reversal, amount: original.amount, date: date ?? today,
                fromAccountId: original.toAccountId, toAccountId: original.fromAccountId,
                contactId: original.contactId, categoryId: original.categoryId,
                note: reason.isEmpty ? original.note : reason,
                reversesTransactionId: original.id, eventGroupId: original.eventGroupId,
                chequeId: original.chequeId, obligationId: original.obligationId, now: now
            )
            context.insert(rev)
            for s in try fetchAll(Settlement.self) where s.transactionId == original.id && !s.isVoided {
                s.isVoided = true
                s.updatedAt = now
            }
            audit("reverse", "transaction", original.id, reason.isEmpty ? "برگشت تراکنش" : reason)
            return rev.id
        }
    }

    /// Editing a money-moving transaction = reverse the old one + record the corrected one, atomically.
    @discardableResult
    func correctTransaction(_ id: UUID, amount: Money, accountId: UUID?, date: CivilDate,
                            categoryId: UUID?, note: String) throws -> UUID {
        let ledger = try loadSnapshot()
        let original = try LedgerRules.validateReversal(transactionId: id, in: ledger)
        guard original.kind == .income || original.kind == .expense else {
            throw DomainError.hasDependencies("تسویه یا انتقال (برای اصلاح، برگشت بزن و دوباره ثبت کن)")
        }
        try LedgerRules.requirePositive(amount)
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        return try atomic("correct") {
            let rev = MoneyTransaction(
                kind: .reversal, amount: original.amount, date: today,
                fromAccountId: original.toAccountId, toAccountId: original.fromAccountId,
                contactId: original.contactId, categoryId: original.categoryId, note: "اصلاح: \(original.note)",
                reversesTransactionId: original.id, eventGroupId: original.eventGroupId, now: now
            )
            context.insert(rev)
            let isExpense = original.kind == .expense
            let tx = MoneyTransaction(
                kind: original.kind, amount: amount, date: date,
                fromAccountId: isExpense ? accountId : nil, toAccountId: isExpense ? nil : accountId,
                contactId: original.contactId, categoryId: categoryId, note: note,
                recurrenceKey: original.recurrenceKey, eventGroupId: original.eventGroupId, now: now
            )
            context.insert(tx)
            audit("correct", "transaction", original.id, "اصلاح تراکنش با برگشت و ثبت مجدد")
            return tx.id
        }
    }

    // MARK: - Obligations

    @discardableResult
    func createObligation(direction: ObligationDirection, contactId: UUID, amount: Money, dueDate: CivilDate?,
                          confidence: ReceiptConfidence = .expected, note: String = "", createdOn: CivilDate? = nil) throws -> UUID {
        try LedgerRules.requirePositive(amount)
        _ = try contact(contactId)
        return try atomic("createObligation") {
            let o = Obligation(direction: direction, contactId: contactId, principal: amount, dueDate: dueDate,
                               createdOn: createdOn ?? today, confidence: confidence, note: note, now: now)
            context.insert(o)
            audit("create", "obligation", o.id, direction == .receivable ? "ثبت طلب" : "ثبت بدهی")
            return o.id
        }
    }

    func updateObligation(_ id: UUID, dueDate: CivilDate?, confidence: ReceiptConfidence, note: String) throws {
        try atomic("updateObligation") {
            let o = try obligation(id)
            o.dueDayNumber = dueDate?.dayNumber
            o.confidenceRaw = confidence.rawValue
            o.note = note
            o.updatedAt = now
            audit("update", "obligation", id, "تغییر سررسید/یادداشت")
        }
    }

    func cancelObligation(_ id: UUID) throws {
        try atomic("cancelObligation") {
            let o = try obligation(id)
            o.isCancelled = true
            o.updatedAt = now
            audit("cancel", "obligation", id, "لغو طلب/بدهی")
        }
    }

    /// Partial or full real settlement of a receivable (money in) or payable (money out).
    @discardableResult
    func settleObligation(_ id: UUID, amount: Money, accountId: UUID?, date: CivilDate, note: String = "") throws -> UUID {
        let ledger = try loadSnapshot()
        let o = try LedgerRules.validateObligationSettlement(obligationId: id, amount: amount, in: ledger)
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        return try atomic("settleObligation") {
            let group = UUID()
            let incoming = o.direction == .receivable
            let tx = MoneyTransaction(
                kind: incoming ? .settlementIn : .settlementOut, amount: amount, date: date,
                fromAccountId: incoming ? nil : accountId, toAccountId: incoming ? accountId : nil,
                contactId: o.contactId, note: note, eventGroupId: group, obligationId: o.id, now: now
            )
            context.insert(tx)
            context.insert(Settlement(obligationId: o.id, amount: amount, date: date, method: .cash,
                                      transactionId: tx.id, groupId: group, now: now))
            audit("settle", "obligation", o.id, "تسویه نقدی")
            return tx.id
        }
    }

    /// Explicit offset (تهاتر) of a receivable against a payable of the same person. No cash moves.
    func offsetObligations(receivableId: UUID, payableId: UUID, amount: Money, date: CivilDate) throws {
        try LedgerRules.validateOffset(receivableId: receivableId, payableId: payableId, amount: amount, in: try loadSnapshot())
        try atomic("offset") {
            let group = UUID()
            context.insert(Settlement(obligationId: receivableId, amount: amount, date: date, method: .offset,
                                      transactionId: nil, groupId: group, now: now))
            context.insert(Settlement(obligationId: payableId, amount: amount, date: date, method: .offset,
                                      transactionId: nil, groupId: group, now: now))
            audit("offset", "obligation", receivableId, "تهاتر طلب و بدهی")
        }
    }

    /// Undo an offset group: both settlements are voided together.
    func voidOffset(groupId: UUID) throws {
        try atomic("voidOffset") {
            for s in try fetchAll(Settlement.self) where s.groupId == groupId && s.methodRaw == SettlementMethod.offset.rawValue {
                s.isVoided = true
                s.updatedAt = now
            }
            audit("void", "settlement", groupId, "لغو تهاتر")
        }
    }

    // MARK: - Cheques

    @discardableResult
    func createCheque(direction: ChequeDirection, amount: Money, dueDate: CivilDate, contactId: UUID?,
                      bankName: String = "", accountId: UUID? = nil, chequeNumber: String = "", sayadId: String = "",
                      obligationId: UUID? = nil, confidence: ReceiptConfidence = .expected, note: String = "") throws -> UUID {
        try LedgerRules.requirePositive(amount)
        guard contactId != nil else { throw DomainError.contactRequired }
        if let obligationId {
            let o = try obligation(obligationId).snapshot
            let expected: ObligationDirection = direction == .issued ? .payable : .receivable
            guard o.direction == expected, o.contactId == contactId else { throw DomainError.invalidOffset }
        }
        return try atomic("createCheque") {
            let c = Cheque(direction: direction, amount: amount, dueDate: dueDate, contactId: contactId, bankName: bankName,
                           accountId: accountId, chequeNumber: chequeNumber, sayadId: sayadId, obligationId: obligationId,
                           confidence: confidence, note: note, now: now)
            context.insert(c)
            audit("create", "cheque", c.id, direction == .issued ? "ثبت چک صادره" : "ثبت چک دریافتی")
            return c.id
        }
    }

    /// Real payment (issued) or collection (received) of a cheque — fully or partially.
    /// Creates exactly one cash transaction; also settles the linked obligation by the same amount.
    @discardableResult
    func settleCheque(_ id: UUID, amount: Money, accountId: UUID?, date: CivilDate) throws -> UUID {
        let ledger = try loadSnapshot()
        let c = try LedgerRules.validateChequeSettlement(chequeId: id, amount: amount, in: ledger)
        _ = try LedgerRules.requireActiveAccount(accountId, in: ledger)
        return try atomic("settleCheque") {
            let group = UUID()
            let incoming = c.direction == .received
            let tx = MoneyTransaction(
                kind: incoming ? .settlementIn : .settlementOut, amount: amount, date: date,
                fromAccountId: incoming ? nil : accountId, toAccountId: incoming ? accountId : nil,
                contactId: c.contactId, note: incoming ? "وصول چک" : "پرداخت چک", eventGroupId: group,
                chequeId: c.id, obligationId: c.obligationId, now: now
            )
            context.insert(tx)
            context.insert(Settlement(chequeId: c.id, amount: amount, date: date, method: .cash,
                                      transactionId: tx.id, groupId: group, now: now))
            if let oid = c.obligationId, let o = ledger.obligation(oid), !o.isCancelled {
                context.insert(Settlement(obligationId: oid, amount: amount, date: date, method: .cash,
                                          transactionId: tx.id, groupId: group, now: now))
            }
            audit("settle", "cheque", c.id, incoming ? "وصول چک" : "پرداخت چک")
            return tx.id
        }
    }

    /// Bounced cheque: any recorded cash settlement of it is reversed, its settlements voided and the
    /// linked obligation (if any) re-opens automatically because its settlements are voided too.
    func bounceCheque(_ id: UUID, date: CivilDate) throws {
        let ledger = try loadSnapshot()
        guard let c = ledger.cheque(id) else { throw DomainError.notFound }
        guard c.lifecycle == .active else { throw DomainError.chequeNotActive }
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        try atomic("bounce") {
            let txIds = Set(ledger.settlements.filter { $0.chequeId == id && !$0.isVoided }.compactMap(\.transactionId))
            for txId in txIds where !reversed.contains(txId) {
                guard let original = ledger.transaction(txId) else { continue }
                context.insert(MoneyTransaction(
                    kind: .reversal, amount: original.amount, date: date,
                    fromAccountId: original.toAccountId, toAccountId: original.fromAccountId,
                    contactId: original.contactId, note: "برگشت چک",
                    reversesTransactionId: original.id, eventGroupId: original.eventGroupId,
                    chequeId: id, obligationId: original.obligationId, now: now
                ))
            }
            for s in try fetchAll(Settlement.self) where !s.isVoided && (s.chequeId == id || (s.transactionId.map { txIds.contains($0) } ?? false)) {
                s.isVoided = true
                s.updatedAt = now
            }
            let model = try cheque(id)
            model.lifecycleRaw = ChequeLifecycle.bounced.rawValue
            model.updatedAt = now
            audit("bounce", "cheque", id, "برگشت چک")
        }
    }

    func setChequeLifecycle(_ id: UUID, _ lifecycle: ChequeLifecycle) throws {
        let ledger = try loadSnapshot()
        guard let c = ledger.cheque(id) else { throw DomainError.notFound }
        if lifecycle == .cancelled || lifecycle == .returned {
            let settledAmount = try FinancialCalculator.settled(chequeId: id, settlements: ledger.settlements)
            guard settledAmount.isZero else { throw DomainError.hasDependencies("پرداخت/وصول ثبت‌شده (ابتدا برگشت بزن)") }
        }
        guard c.lifecycle != lifecycle else { return }
        try atomic("chequeLifecycle") {
            let model = try cheque(id)
            model.lifecycleRaw = lifecycle.rawValue
            model.updatedAt = now
            audit("lifecycle", "cheque", id, "تغییر وضعیت چک به \(lifecycle.rawValue)")
        }
    }

    func rescheduleCheque(_ id: UUID, newDueDate: CivilDate) throws {
        try atomic("rescheduleCheque") {
            let model = try cheque(id)
            let old = CivilDate(dayNumber: model.dueDayNumber)
            model.dueDayNumber = newDueDate.dayNumber
            model.updatedAt = now
            audit("reschedule", "cheque", id, "تمدید سررسید از \(PersianFormat.date(old)) به \(PersianFormat.date(newDueDate))")
        }
    }

    func updateChequeDetails(_ id: UUID, bankName: String, chequeNumber: String, sayadId: String, note: String,
                             confidence: ReceiptConfidence) throws {
        try atomic("updateCheque") {
            let model = try cheque(id)
            model.bankName = bankName
            model.chequeNumber = chequeNumber
            model.sayadId = sayadId
            model.note = note
            model.confidenceRaw = confidence.rawValue
            model.updatedAt = now
        }
    }

    func setChequeAttachment(_ chequeId: UUID, attachmentId: UUID?) throws {
        try atomic("chequeAttachment") {
            let model = try cheque(chequeId)
            model.attachmentId = attachmentId
            model.updatedAt = now
        }
    }

    func chequeAttachmentId(_ chequeId: UUID) throws -> UUID? {
        try cheque(chequeId).attachmentId
    }

    // MARK: - Recurring

    @discardableResult
    func addRecurringRule(title: String, kind: TransactionKind, amount: Money, accountId: UUID?, categoryId: UUID?,
                          startDate: CivilDate, endDate: CivilDate?, frequency: RecurrenceFrequency, interval: Int = 1,
                          monthEndPolicy: MonthEndPolicy = .lastValidDay, confidence: ReceiptConfidence = .confirmed) throws -> UUID {
        guard kind == .income || kind == .expense else { throw DomainError.invalidOffset }
        try LedgerRules.requirePositive(amount)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.nameRequired }
        if let endDate, endDate < startDate { throw DomainError.invalidDate }
        return try atomic("addRule") {
            let r = RecurringRule(title: trimmed, kind: kind, amount: amount, accountId: accountId, categoryId: categoryId,
                                  startDate: startDate, endDate: endDate, frequency: frequency, interval: max(1, interval),
                                  monthEndPolicy: monthEndPolicy, confidence: confidence, now: now)
            context.insert(r)
            audit("create", "recurring", r.id, "ایجاد قاعده تکرار")
            return r.id
        }
    }

    func setRecurringRuleActive(_ id: UUID, active: Bool) throws {
        try atomic("ruleActive") {
            let r = try find(RecurringRule.self) { $0.id == id }
            r.isActive = active
            r.updatedAt = now
        }
    }

    /// Records the real transaction for one recurring occurrence; the forecast then skips that occurrence.
    @discardableResult
    func confirmOccurrence(_ occurrence: RecurringOccurrence, amount: Money, accountId: UUID?, date: CivilDate) throws -> UUID {
        let rule = occurrence.rule
        if rule.kind == .income {
            return try recordIncome(amount: amount, accountId: accountId, date: date, categoryId: rule.categoryId,
                                    note: rule.title, recurrenceKey: occurrence.key)
        }
        return try recordExpense(amount: amount, accountId: accountId, date: date, categoryId: rule.categoryId,
                                 note: rule.title, recurrenceKey: occurrence.key)
    }

    // MARK: - Attachments & wipe

    func addAttachment(ownerId: UUID, fileName: String) throws -> UUID {
        try atomic("attachment") {
            let a = Attachment(ownerId: ownerId, fileName: fileName, now: now)
            context.insert(a)
            return a.id
        }
    }

    func attachments() throws -> [Attachment] { try fetchAll(Attachment.self) }

    func auditEvents() throws -> [AuditEvent] {
        try fetchAll(AuditEvent.self).sorted { $0.timestamp > $1.timestamp }
    }

    /// Deletes every record. Caller is responsible for the double confirmation.
    func wipeAll() throws {
        try atomic("wipe") {
            try deleteEverything()
        }
    }

    /// Deletes all records without saving (used inside larger atomic operations such as restore).
    func deleteEverything() throws {
        try fetchAll(FinancialAccount.self).forEach { context.delete($0) }
        try fetchAll(Contact.self).forEach { context.delete($0) }
        try fetchAll(MoneyTransaction.self).forEach { context.delete($0) }
        try fetchAll(Obligation.self).forEach { context.delete($0) }
        try fetchAll(Cheque.self).forEach { context.delete($0) }
        try fetchAll(Settlement.self).forEach { context.delete($0) }
        try fetchAll(RecurringRule.self).forEach { context.delete($0) }
        try fetchAll(Budget.self).forEach { context.delete($0) }
        try fetchAll(ExpenseCategory.self).forEach { context.delete($0) }
        try fetchAll(Attachment.self).forEach { context.delete($0) }
        try fetchAll(AuditEvent.self).forEach { context.delete($0) }
    }

    /// Runs `body` and saves once; rolls back everything if it throws.
    func performAtomically(_ body: () throws -> Void) throws {
        try atomic("custom", body)
    }
}
