import UserNotifications
import XCTest
@testable import Chortkeh

final class ReminderPlannerTests: XCTestCase {
    typealias B = LedgerBuilder
    let tehran = TimeZone(identifier: "Asia/Tehran")!

    private func now(_ b: B, hour: Int = 8) -> Date { b.today.date(hour: hour, timeZone: tehran) }

    func testDefaultOffsetsAndStableIds() throws {
        var b = B()
        let p = b.contact("احمدی")
        let ch = b.cheque(.issued, B.m(75), contact: p, dueIn: 10)
        var prefs = ReminderPreferences()
        prefs.dailyExpenseReminder = false
        let plan = try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now(b), timeZone: tehran)
        XCTAssertEqual(plan.map(\.day), [3, 7, 9, 10].map { b.today.adding(days: $0) })
        XCTAssertEqual(plan.first?.id, "chortkeh.due.cheque:\(ch.uuidString).7")
        let again = try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now(b), timeZone: tehran)
        XCTAssertEqual(plan, again)
    }

    func testPastOffsetsAreSkippedAndPrivacyByDefault() throws {
        var b = B()
        let p = b.contact("احمدی")
        b.cheque(.issued, B.m(75), contact: p, dueIn: 2)
        var prefs = ReminderPreferences()
        prefs.dailyExpenseReminder = false
        let plan = try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now(b, hour: 10), timeZone: tehran)
        // 7 and 3 days before are in the past; offset 1 (tomorrow 9:00) and 0 remain.
        XCTAssertEqual(plan.count, 2)
        XCTAssertFalse(plan[0].body.contains("احمدی"))
        XCTAssertFalse(plan[0].body.contains("۷۵"))
        prefs.showDetails = true
        let detailed = try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now(b, hour: 10), timeZone: tehran)
        XCTAssertTrue(detailed[0].body.contains("احمدی"))
    }

    func testSettledItemsProduceNoReminderAndLimitIsRespected() throws {
        var b = B()
        let p = b.contact("احمدی")
        let ch = b.cheque(.issued, B.m(1), contact: p, dueIn: 10)
        b.settle(cheque: ch, B.m(1))
        for i in 0..<40 { b.cheque(.issued, B.m(1), contact: p, dueIn: 10 + i) }
        let plan = try ReminderPlanner.plan(ledger: b.ledger, preferences: ReminderPreferences(), unit: .toman, now: now(b), timeZone: tehran)
        XCTAssertFalse(plan.contains { $0.id.contains(ch.uuidString) })
        XCTAssertEqual(plan.count, ReminderPlanner.maxPending)
        XCTAssertEqual(plan.last?.id, ReminderPlanner.dailyId)
        XCTAssertTrue(plan.last!.repeatsDaily)
    }
}

/// Scenario 17: reminders follow changes — re-dated or settled items replace/remove old notifications.
final class ReminderSchedulerTests: XCTestCase {
    final class FakeCenter: NotificationCenterClient {
        var pending: [String: UNNotificationRequest] = [:]
        var status: UNAuthorizationStatus = .authorized

        func pendingIdentifiers() async -> [String] { Array(pending.keys) }
        func removePending(identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
        func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async throws -> Bool { status == .authorized }
    }

    func testRescheduleReplacesAndRemoves() async throws {
        typealias B = LedgerBuilder
        let tz = TimeZone(identifier: "Asia/Tehran")!
        var b = B()
        let p = b.contact("احمدی")
        let ch = b.cheque(.issued, B.m(10), contact: p, dueIn: 10)
        let center = FakeCenter()
        center.pending["other.app.reminder"] = UNNotificationRequest(identifier: "other.app.reminder", content: UNMutableNotificationContent(), trigger: nil)
        let scheduler = ReminderScheduler(center: center)
        var prefs = ReminderPreferences()
        prefs.dailyExpenseReminder = false
        let now = b.today.date(hour: 8, timeZone: tz)

        await scheduler.sync(try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now, timeZone: tz))
        XCTAssertEqual(center.pending.keys.filter { $0.hasPrefix("chortkeh.") }.count, 4)
        let trigger = center.pending["chortkeh.due.cheque:\(ch.uuidString).0"]?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.day, b.today.adding(days: 10).gregorian.day)

        // Due date moved 20 days later: same ids, new dates.
        b.ledger.cheques[0].dueDate = b.today.adding(days: 30)
        await scheduler.sync(try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now, timeZone: tz))
        let moved = center.pending["chortkeh.due.cheque:\(ch.uuidString).0"]?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(moved?.dateComponents.day, b.today.adding(days: 30).gregorian.day)

        // Settled: all of its reminders disappear; foreign notifications are untouched.
        b.settle(cheque: ch, B.m(10))
        await scheduler.sync(try ReminderPlanner.plan(ledger: b.ledger, preferences: prefs, unit: .toman, now: now, timeZone: tz))
        XCTAssertEqual(center.pending.keys.filter { $0.hasPrefix("chortkeh.") }.count, 0)
        XCTAssertNotNil(center.pending["other.app.reminder"])
    }

    // Scenario 21: no notification permission → nothing scheduled, nothing crashes.
    func testDeniedPermissionSchedulesNothing() async throws {
        let center = FakeCenter()
        center.status = .denied
        var b = LedgerBuilder()
        let p = b.contact("احمدی")
        b.cheque(.issued, LedgerBuilder.m(10), contact: p, dueIn: 10)
        let added = await ReminderScheduler(center: center).sync(
            try ReminderPlanner.plan(ledger: b.ledger, preferences: ReminderPreferences(), unit: .toman, now: Date())
        )
        XCTAssertEqual(added, 0)
        XCTAssertTrue(center.pending.isEmpty)
    }
}

final class BackupCryptoTests: XCTestCase {
    func testRoundTripAndWrongPassword() throws {
        let plain = Data("سلام چرتکه 123".utf8)
        let sealed = try BackupCrypto.encrypt(plain, password: "رمز-خیلی-امن", iterations: 2_000)
        XCTAssertEqual(Array(sealed.prefix(8)), BackupCrypto.magic)
        XCTAssertEqual(try BackupCrypto.decrypt(sealed, password: "رمز-خیلی-امن"), plain)
        XCTAssertThrowsError(try BackupCrypto.decrypt(sealed, password: "رمز-اشتباه-است")) {
            XCTAssertEqual($0 as? DomainError, .backupWrongPassword)
        }
    }

    func testTamperedHeaderOrBodyIsRejected() throws {
        let sealed = try BackupCrypto.encrypt(Data("data".utf8), password: "password-123", iterations: 2_000)
        var body = sealed
        body[body.count - 1] ^= 0x01
        XCTAssertThrowsError(try BackupCrypto.decrypt(body, password: "password-123"))
        var header = sealed
        header[20] ^= 0x01 // salt byte → different key
        XCTAssertThrowsError(try BackupCrypto.decrypt(header, password: "password-123"))
        XCTAssertThrowsError(try BackupCrypto.decrypt(Data("not a backup".utf8), password: "password-123")) {
            XCTAssertEqual($0 as? DomainError, .backupCorrupted)
        }
    }

    func testShortPasswordRejectedAndSaltIsRandom() throws {
        XCTAssertThrowsError(try BackupCrypto.encrypt(Data(), password: "short")) {
            XCTAssertEqual($0 as? DomainError, .passwordTooShort)
        }
        let a = try BackupCrypto.encrypt(Data("x".utf8), password: "password-123", iterations: 2_000)
        let b = try BackupCrypto.encrypt(Data("x".utf8), password: "password-123", iterations: 2_000)
        XCTAssertNotEqual(a, b)
    }

    func testCSVEscapingAndBOM() {
        var b = LedgerBuilder()
        let acc = b.account("ملت, مرکزی", opening: .zero)
        b.tx(.expense, LedgerBuilder.t(1_000), from: acc)
        b.ledger.transactions[0].note = "=HYPERLINK(\"x\")"
        let csv = ReportExporter.transactionsCSV(b.ledger, unit: .toman)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"ملت, مرکزی\""))
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        XCTAssertTrue(csv.contains(",1000,"))
    }
}
