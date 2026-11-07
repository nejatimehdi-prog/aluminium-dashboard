import Foundation

struct PlannedReminder: Equatable, Sendable {
    /// Stable identifier. Re-planning produces the same id for the same commitment/offset,
    /// so a changed due date replaces (not duplicates) the pending notification.
    let id: String
    let day: CivilDate
    let hour: Int
    let minute: Int
    let title: String
    let body: String
    let repeatsDaily: Bool
}

/// Decides which local notifications should exist. Pure, so it is fully unit-testable.
enum ReminderPlanner {
    static let idPrefix = "chortkeh."
    /// iOS keeps at most 64 pending local notifications per app; stay below it.
    static let maxPending = 60
    static let dailyId = "chortkeh.daily-expense"

    static func plan(
        ledger: LedgerSnapshot,
        preferences: ReminderPreferences,
        unit: CurrencyUnit,
        now: Date,
        timeZone: TimeZone = .current
    ) throws -> [PlannedReminder] {
        let today = CivilDate.from(now, timeZone: timeZone)
        var planned: [(fire: Date, reminder: PlannedReminder)] = []

        if preferences.dueRemindersEnabled {
            for c in try CommitmentResolver.commitments(ledger, today: today) {
                guard let due = c.dueDate else { continue }
                if due < today {
                    guard preferences.overdueAlerts else { continue }
                    let day = today.adding(days: 1)
                    let reminder = PlannedReminder(
                        id: "\(idPrefix)overdue.\(c.ownerId)",
                        day: day,
                        hour: preferences.hour,
                        minute: preferences.minute,
                        title: "چُرتکه",
                        body: body(for: c, ledger: ledger, unit: unit, daysLeft: today.days(until: due), details: preferences.showDetails),
                        repeatsDaily: false
                    )
                    planned.append((day.date(hour: preferences.hour, minute: preferences.minute, timeZone: timeZone), reminder))
                    continue
                }
                for offset in Set(preferences.offsets).sorted(by: >) where offset >= 0 {
                    let day = due.adding(days: -offset)
                    let fire = day.date(hour: preferences.hour, minute: preferences.minute, timeZone: timeZone)
                    guard fire > now else { continue }
                    planned.append((fire, PlannedReminder(
                        id: "\(idPrefix)due.\(c.ownerId).\(offset)",
                        day: day,
                        hour: preferences.hour,
                        minute: preferences.minute,
                        title: "چُرتکه",
                        body: body(for: c, ledger: ledger, unit: unit, daysLeft: offset, details: preferences.showDetails),
                        repeatsDaily: false
                    )))
                }
            }
        }

        planned.sort { $0.fire == $1.fire ? $0.reminder.id < $1.reminder.id : $0.fire < $1.fire }
        let limit = preferences.dailyExpenseReminder ? maxPending - 1 : maxPending
        var result = planned.prefix(limit).map { $0.reminder }

        if preferences.dailyExpenseReminder {
            result.append(PlannedReminder(
                id: dailyId,
                day: today,
                hour: preferences.dailyHour,
                minute: preferences.dailyMinute,
                title: "چُرتکه",
                body: "هزینه‌های امروز را ثبت کرده‌ای؟",
                repeatsDaily: true
            ))
        }
        return result
    }

    /// Lock-screen text. Generic by default; amount and name only with explicit consent.
    static func body(for c: Commitment, ledger: LedgerSnapshot, unit: CurrencyUnit, daysLeft: Int, details: Bool) -> String {
        let when: String
        if daysLeft < 0 {
            when = "سررسید گذشته است"
        } else if daysLeft == 0 {
            when = "امروز سررسید است"
        } else {
            when = "\(PersianFormat.number(daysLeft)) روز تا سررسید"
        }
        guard details else {
            switch c.flow {
            case .outflow: return "یک پرداخت به سررسید نزدیک است (\(when))."
            case .inflow: return "یک دریافتی به سررسید نزدیک است (\(when))."
            }
        }
        let who = ledger.contact(c.contactId)?.name
        let amount = PersianFormat.money(c.amount, unit: unit)
        let subject = c.kind.title + (who.map { " \($0)" } ?? "")
        return "\(subject): \(amount) — \(when)"
    }
}
