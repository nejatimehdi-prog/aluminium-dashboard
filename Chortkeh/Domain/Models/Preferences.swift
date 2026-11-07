import Foundation

struct ReminderPreferences: Codable, Equatable, Sendable {
    /// Master switch for due-date reminders.
    var dueRemindersEnabled: Bool = true
    /// Days before the due date (0 = on the due date).
    var offsets: [Int] = [7, 3, 1, 0]
    var hour: Int = 9
    var minute: Int = 0
    /// Remind once about items that are already overdue.
    var overdueAlerts: Bool = true
    /// Show amount and person on the lock screen. Off by default (privacy).
    var showDetails: Bool = false
    var dailyExpenseReminder: Bool = true
    var dailyHour: Int = 21
    var dailyMinute: Int = 0
}

/// User-adjustable settings, persisted as one JSON blob.
struct AppPreferences: Codable, Equatable, Sendable {
    var unit: CurrencyUnit = .toman
    /// Amount the user wants to keep untouched, in rials.
    var reserve: Money = .zero
    var horizonDays: Int = 30
    var scenario: ForecastScenario = .normal
    var lockEnabled: Bool = false
    var hidePreviewInAppSwitcher: Bool = true
    var defaultMonthEndPolicy: MonthEndPolicy = .lastValidDay
    var onboardingCompleted: Bool = false
    var reminders = ReminderPreferences()

    init() {}

    // Tolerant decoding: missing keys fall back to defaults so older saved settings keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppPreferences.defaults
        unit = try c.decodeIfPresent(CurrencyUnit.self, forKey: .unit) ?? d.unit
        reserve = try c.decodeIfPresent(Money.self, forKey: .reserve) ?? d.reserve
        horizonDays = try c.decodeIfPresent(Int.self, forKey: .horizonDays) ?? d.horizonDays
        scenario = try c.decodeIfPresent(ForecastScenario.self, forKey: .scenario) ?? d.scenario
        lockEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockEnabled) ?? d.lockEnabled
        hidePreviewInAppSwitcher = try c.decodeIfPresent(Bool.self, forKey: .hidePreviewInAppSwitcher) ?? d.hidePreviewInAppSwitcher
        defaultMonthEndPolicy = try c.decodeIfPresent(MonthEndPolicy.self, forKey: .defaultMonthEndPolicy) ?? d.defaultMonthEndPolicy
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
        reminders = try c.decodeIfPresent(ReminderPreferences.self, forKey: .reminders) ?? d.reminders
    }

    static let defaults = AppPreferences()
}
