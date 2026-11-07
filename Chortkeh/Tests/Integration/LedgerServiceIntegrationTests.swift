import SwiftData
import XCTest
@testable import Chortkeh

/// End-to-end tests through the real SwiftData store (in memory): scenarios 1–10, 16, 18, 20.
@MainActor
final class LedgerServiceIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var service: LedgerService!
    let fixedNow = CivilDate(jalaliYear: 1405, month: 8, day: 16)!.date(hour: 10)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        let now = fixedNow
        service = LedgerService(context: container.mainContext, clock: { now })
        try service.seedDefaultCategoriesIfNeeded()
    }

    private func m(_ million: Int64) -> Money { try! Money.toman(million * 1_000_000) }
    private var today: CivilDate { service.today }
    private func cash() throws -> Money { try FinancialCalculator.totalCash(service.loadSnapshot()) }

    func testScenario1And2ExpenseAndTransfer() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(200))
        let b = try service.addAccount(name: "نقد", kind: .cash, openingBalance: .zero)
        try service.recordExpense(amount: m(10), accountId: a, date: today)
        XCTAssertEqual(try cash(), m(190))
        try service.transfer(amount: m(50), from: a, to: b, date: today)
        XCTAssertEqual(try cash(), m(190))
        XCTAssertEqual(try FinancialCalculator.balance(of: b, in: service.loadSnapshot()), m(50))
        XCTAssertThrowsError(try service.transfer(amount: m(1), from: a, to: a, date: today)) {
            XCTAssertEqual($0 as? DomainError, .sameAccountTransfer)
        }
    }

    func testRejectsZeroOrNegativeAndMissingAccount() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(1))
        XCTAssertThrowsError(try service.recordExpense(amount: .zero, accountId: a, date: today))
        XCTAssertThrowsError(try service.recordExpense(amount: Money(rials: -10), accountId: a, date: today))
        XCTAssertThrowsError(try service.recordExpense(amount: m(1), accountId: nil, date: today)) {
            XCTAssertEqual($0 as? DomainError, .accountRequired)
        }
        XCTAssertEqual(try service.loadSnapshot().transactions.count, 0)
    }

    func testScenario3To5ChequesAndLinkedDebt() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(200))
        let ahmadi = try service.contactId(named: "احمدی")
        let rezaei = try service.contactId(named: "رضایی")
        let debt = try service.createObligation(direction: .payable, contactId: ahmadi, amount: m(80), dueDate: today.adding(days: 10))
        let issued = try service.createCheque(direction: .issued, amount: m(80), dueDate: today.adding(days: 10),
                                              contactId: ahmadi, obligationId: debt)
        let received = try service.createCheque(direction: .received, amount: m(40), dueDate: today.adding(days: 5),
                                                contactId: rezaei, confidence: .confirmed)
        XCTAssertEqual(try cash(), m(200), "Cheques alone never change cash")

        let f = try ForecastEngine.run(ForecastInput(ledger: service.loadSnapshot(), today: today, horizonDays: 30,
                                                     scenario: .normal, reserve: .zero, includeDailySpending: false))
        XCTAssertEqual(f.events.filter { $0.amount.isNegative }.count, 1, "Debt + linked cheque = one outflow")
        XCTAssertEqual(f.endBalance, m(160))

        try service.settleCheque(received, amount: m(40), accountId: a, date: today.adding(days: 5))
        XCTAssertEqual(try cash(), m(240))
        XCTAssertThrowsError(try service.settleCheque(received, amount: m(1), accountId: a, date: today)) {
            XCTAssertEqual($0 as? DomainError, .nothingOutstanding)
        }

        try service.settleCheque(issued, amount: m(80), accountId: a, date: today.adding(days: 10))
        let s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.totalCash(s), m(160))
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(debt)!, settlements: s.settlements), .zero)
        XCTAssertEqual(s.transactions.filter { $0.chequeId == issued }.count, 1, "One cash transaction per cheque payment")
    }

    func testScenario6And7PartialSettlements() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: .zero)
        let p = try service.contactId(named: "رضایی")
        let r = try service.createObligation(direction: .receivable, contactId: p, amount: m(100), dueDate: today.adding(days: 20))
        try service.settleObligation(r, amount: m(30), accountId: a, date: today)
        var s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(r)!, settlements: s.settlements), m(70))
        XCTAssertThrowsError(try service.settleObligation(r, amount: m(71), accountId: a, date: today))

        let ch = try service.createCheque(direction: .issued, amount: m(90), dueDate: today, contactId: p)
        try service.addAccount(name: "سامان", kind: .bank, openingBalance: m(500))
        let saman = try service.loadSnapshot().accounts.first { $0.name == "سامان" }!.id
        try service.settleCheque(ch, amount: m(30), accountId: saman, date: today)
        try service.settleCheque(ch, amount: m(60), accountId: saman, date: today)
        XCTAssertThrowsError(try service.settleCheque(ch, amount: m(1), accountId: saman, date: today))
        s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.status(of: s.cheque(ch)!, settlements: s.settlements, today: today), .settled)
    }

    func testScenario8BounceReversesCollectionAndReopensDebt() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(10))
        let p = try service.contactId(named: "کریمی")
        let r = try service.createObligation(direction: .receivable, contactId: p, amount: m(50), dueDate: today)
        let ch = try service.createCheque(direction: .received, amount: m(50), dueDate: today, contactId: p, obligationId: r)
        try service.settleCheque(ch, amount: m(50), accountId: a, date: today)
        XCTAssertEqual(try cash(), m(60))
        try service.bounceCheque(ch, date: today.adding(days: 2))
        let s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.totalCash(s), m(10), "Bounce reverses the recorded collection")
        XCTAssertEqual(s.cheque(ch)?.lifecycle, .bounced)
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(r)!, settlements: s.settlements), m(50))
        XCTAssertEqual(s.transactions.filter { $0.kind == .reversal }.count, 1)
        XCTAssertThrowsError(try service.settleCheque(ch, amount: m(1), accountId: a, date: today)) {
            XCTAssertEqual($0 as? DomainError, .chequeNotActive)
        }
    }

    func testScenario9OffsetNeedsExplicitCallAndKeepsCash() throws {
        _ = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(5))
        let p = try service.contactId(named: "کریمی")
        let r = try service.createObligation(direction: .receivable, contactId: p, amount: m(30), dueDate: nil)
        let d = try service.createObligation(direction: .payable, contactId: p, amount: m(20), dueDate: nil)
        var s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(r)!, settlements: s.settlements), m(30), "No automatic netting")
        try service.offsetObligations(receivableId: r, payableId: d, amount: m(20), date: today)
        s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(r)!, settlements: s.settlements), m(10))
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(d)!, settlements: s.settlements), .zero)
        XCTAssertEqual(try FinancialCalculator.totalCash(s), m(5))
        let group = s.settlements.first!.groupId
        try service.voidOffset(groupId: group)
        s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(d)!, settlements: s.settlements), m(20))
    }

    func testScenario10RecurringConfirmation() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(1))
        try service.addRecurringRule(title: "حقوق", kind: .income, amount: m(30), accountId: a, categoryId: nil,
                                     startDate: today.adding(days: 1), endDate: nil, frequency: .monthly)
        var s = try service.loadSnapshot()
        let occ = try RecurringSchedule.pendingOccurrences(s, from: today, through: today.adding(days: 1))
        XCTAssertEqual(occ.count, 1)
        try service.confirmOccurrence(occ[0], amount: m(30), accountId: a, date: today.adding(days: 1))
        s = try service.loadSnapshot()
        XCTAssertTrue(try RecurringSchedule.pendingOccurrences(s, from: today, through: today.adding(days: 1)).isEmpty)
    }

    func testScenario16ReverseAndCorrect() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(100))
        let e = try service.recordExpense(amount: m(10), accountId: a, date: today, note: "خرید")
        let corrected = try service.correctTransaction(e, amount: m(12), accountId: a, date: today, categoryId: nil, note: "خرید اصلاح‌شده")
        XCTAssertEqual(try cash(), m(88))
        XCTAssertThrowsError(try service.reverseTransaction(e)) { XCTAssertEqual($0 as? DomainError, .alreadyReversed) }
        try service.reverseTransaction(corrected)
        XCTAssertEqual(try cash(), m(100))
        let totals = try FinancialCalculator.periodTotals(service.loadSnapshot(), from: today, through: today)
        XCTAssertEqual(totals.expense, .zero)
        XCTAssertFalse(try service.auditEvents().isEmpty)
    }

    func testReversingASettlementReopensTheDebt() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(100))
        let p = try service.contactId(named: "احمدی")
        let d = try service.createObligation(direction: .payable, contactId: p, amount: m(40), dueDate: today)
        let tx = try service.settleObligation(d, amount: m(40), accountId: a, date: today)
        XCTAssertEqual(try cash(), m(60))
        try service.reverseTransaction(tx)
        let s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.totalCash(s), m(100))
        XCTAssertEqual(try FinancialCalculator.outstanding(of: s.obligation(d)!, settlements: s.settlements), m(40))
    }

    func testAdjustmentIsVisibleAndDependentDeletesAreBlocked() throws {
        let a = try service.addAccount(name: "ملت", kind: .bank, openingBalance: m(100))
        try service.recordExpense(amount: m(10), accountId: a, date: today)
        XCTAssertThrowsError(try service.setOpeningBalance(a, amount: m(1)))
        try service.adjustBalance(accountId: a, actual: m(95), date: today)
        let s = try service.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.totalCash(s), m(95))
        XCTAssertEqual(s.transactions.filter { $0.kind == .adjustmentIn }.count, 1)
        XCTAssertThrowsError(try service.deleteAccount(a))
        let p = try service.contactId(named: "احمدی")
        try service.createObligation(direction: .payable, contactId: p, amount: m(1), dueDate: nil)
        XCTAssertThrowsError(try service.deleteContact(p))
    }

    func testDataSurvivesContainerReopen() throws {
        // Scenario 19/20: persistence works fully offline on a file store.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        let schema = Schema(versionedSchema: SchemaV1.self)
        do {
            let c = try ModelContainer(for: schema, migrationPlan: ChortkehMigrationPlan.self,
                                       configurations: [ModelConfiguration(schema: schema, url: url)])
            let s = LedgerService(context: c.mainContext)
            try s.addAccount(name: "ملت", kind: .bank, openingBalance: try Money.toman(9_999_999_999_999))
        }
        let c2 = try ModelContainer(for: schema, migrationPlan: ChortkehMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: schema, url: url)])
        let snapshot = try LedgerService(context: c2.mainContext).loadSnapshot()
        XCTAssertEqual(snapshot.accounts.first?.openingBalance, try Money.toman(9_999_999_999_999))
    }
}

/// Scenario 18: backup and restore, wrong password, and failure without damaging existing data.
@MainActor
final class BackupRestoreIntegrationTests: XCTestCase {
    private func makeService() throws -> LedgerService {
        let c = try PersistenceController.makeContainer(inMemory: true)
        retained.append(c)
        return LedgerService(context: c.mainContext)
    }

    private var retained: [ModelContainer] = []
    private func m(_ million: Int64) -> Money { try! Money.toman(million * 1_000_000) }

    func testBackupRoundTrip() throws {
        let source = try makeService()
        try source.seedDefaultCategoriesIfNeeded()
        let a = try source.addAccount(name: "ملت", kind: .bank, openingBalance: m(200))
        let p = try source.contactId(named: "احمدی")
        let d = try source.createObligation(direction: .payable, contactId: p, amount: m(80), dueDate: source.today.adding(days: 9))
        try source.createCheque(direction: .issued, amount: m(80), dueDate: source.today.adding(days: 9), contactId: p, obligationId: d)
        try source.recordExpense(amount: m(3), accountId: a, date: source.today)
        var prefs = AppPreferences()
        prefs.reserve = m(5)

        let data = try BackupService(service: source, attachmentStore: nil)
            .exportEncrypted(password: "گذرواژه-امن-۱۲۳", preferences: prefs, iterations: 2_000)

        let target = try makeService()
        let backup = BackupService(service: target, attachmentStore: nil)
        XCTAssertThrowsError(try backup.inspect(data, password: "wrong-password")) {
            XCTAssertEqual($0 as? DomainError, .backupWrongPassword)
        }
        let preview = try backup.inspect(data, password: "گذرواژه-امن-۱۲۳")
        XCTAssertEqual(preview.payload.cheques.count, 1)
        XCTAssertEqual(preview.payload.preferences?.reserve, m(5))
        try backup.restore(preview)

        let restored = try target.loadSnapshot()
        let original = try source.loadSnapshot()
        XCTAssertEqual(try FinancialCalculator.totalCash(restored), try FinancialCalculator.totalCash(original))
        XCTAssertEqual(Set(restored.transactions.map(\.id)), Set(original.transactions.map(\.id)))
        XCTAssertEqual(Set(restored.cheques), Set(original.cheques))
        XCTAssertEqual(Set(restored.obligations), Set(original.obligations))
        XCTAssertEqual(restored.categories.count, original.categories.count)
    }

    func testInvalidBackupDoesNotTouchExistingData() throws {
        let target = try makeService()
        try target.addAccount(name: "موجود", kind: .bank, openingBalance: m(42))
        let backup = BackupService(service: target, attachmentStore: nil)

        // A structurally valid but inconsistent payload: transaction points to a missing account.
        var payload = try backup.makePayload(preferences: nil)
        payload.accounts = []
        payload.transactions = [.init(id: UUID(), kind: "expense", amount: 10, day: 0, fromAccountId: UUID(), toAccountId: nil,
                                      contactId: nil, categoryId: nil, note: "", reversesTransactionId: nil, recurrenceKey: nil,
                                      eventGroupId: UUID(), chequeId: nil, obligationId: nil, attachmentId: nil,
                                      createdAt: Date(), updatedAt: Date())]
        let sealed = try BackupCrypto.encrypt(try BackupService.encode(payload), password: "password-123", iterations: 2_000)
        XCTAssertThrowsError(try backup.inspect(sealed, password: "password-123"))
        XCTAssertThrowsError(try backup.restore(BackupPreview(payload: payload)))

        let after = try target.loadSnapshot()
        XCTAssertEqual(after.accounts.count, 1)
        XCTAssertEqual(try FinancialCalculator.totalCash(after), m(42))

        // Garbage and future versions are rejected before anything happens.
        XCTAssertThrowsError(try backup.inspect(Data("garbage".utf8), password: "password-123"))
        var future = try backup.makePayload(preferences: nil)
        future.format = 99
        let futureSealed = try BackupCrypto.encrypt(try BackupService.encode(future), password: "password-123", iterations: 2_000)
        XCTAssertThrowsError(try backup.inspect(futureSealed, password: "password-123")) {
            XCTAssertEqual($0 as? DomainError, .backupUnsupportedVersion(99))
        }
    }

    func testWipeAllRequiresExplicitCallAndClearsEverything() throws {
        let s = try makeService()
        try s.seedDefaultCategoriesIfNeeded()
        try s.addAccount(name: "ملت", kind: .bank, openingBalance: m(1))
        try s.wipeAll()
        let snapshot = try s.loadSnapshot()
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(snapshot.categories.isEmpty)
    }
}
