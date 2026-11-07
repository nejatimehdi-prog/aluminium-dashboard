import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Launch options used by UI tests and previews (never by real users).
struct LaunchOptions {
    var inMemory = false
    var skipOnboarding = false
    var seedAccountToman: Int64?
    var disableLock = false
    var fixedToday: Date?

    static func fromProcess() -> LaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        var o = LaunchOptions()
        o.inMemory = args.contains("-uiTesting")
        o.skipOnboarding = args.contains("-skipOnboarding")
        o.disableLock = args.contains("-uiTesting")
        if let i = args.firstIndex(of: "-seedAccountToman"), i + 1 < args.count {
            o.seedAccountToman = Int64(args[i + 1])
        }
        return o
    }
}

/// Single source of UI state. Loads the ledger, runs the engines and exposes ready-to-render data.
@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    let service: LedgerService
    let preferencesStore: PreferencesStore
    let reminderScheduler: ReminderScheduler
    let attachmentStore: AttachmentStore?
    private let clock: () -> Date

    /// Saved by RootView whenever it changes (see `savePreferences`).
    var preferences: AppPreferences
    var ledger = LedgerSnapshot()
    var dashboard: DashboardData?
    var errorMessage: String?
    var toast: String?
    var isUnlocked: Bool
    var notificationStatus: String = ""

    init(container: ModelContainer, preferencesStore: PreferencesStore, notificationCenter: NotificationCenterClient,
         attachmentStore: AttachmentStore?, clock: @escaping () -> Date = Date.init) {
        self.container = container
        self.service = LedgerService(context: container.mainContext, clock: clock)
        self.preferencesStore = preferencesStore
        self.reminderScheduler = ReminderScheduler(center: notificationCenter)
        self.attachmentStore = attachmentStore
        self.clock = clock
        let prefs = preferencesStore.load()
        self.preferences = prefs
        self.isUnlocked = !prefs.lockEnabled
    }

    static func live(options: LaunchOptions = .fromProcess()) -> AppState {
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: options.inMemory)
        } catch {
            // The store could not be opened. Fall back to memory so the app can still show an error
            // instead of crashing; nothing is deleted on disk.
            container = try! PersistenceController.makeContainer(inMemory: true)
        }
        let prefsStore: PreferencesStore
        if options.inMemory {
            let suite = UserDefaults(suiteName: "chortkeh.uitests") ?? .standard
            suite.removePersistentDomain(forName: "chortkeh.uitests")
            prefsStore = PreferencesStore(defaults: suite)
        } else {
            prefsStore = PreferencesStore()
        }
        let state = AppState(
            container: container,
            preferencesStore: prefsStore,
            notificationCenter: SystemNotificationCenter(),
            attachmentStore: try? AttachmentStore()
        )
        if options.skipOnboarding { state.preferences.onboardingCompleted = true }
        if options.disableLock {
            state.preferences.lockEnabled = false
            state.isUnlocked = true
        }
        try? state.service.seedDefaultCategoriesIfNeeded()
        if let seed = options.seedAccountToman, (try? state.service.fetchAll(FinancialAccount.self).isEmpty) == true {
            if let money = try? Money.toman(seed) {
                _ = try? state.service.addAccount(name: "حساب اصلی", kind: .bank, openingBalance: money)
            }
        }
        state.reload()
        return state
    }

    func savePreferences() {
        preferencesStore.save(preferences)
    }

    var today: CivilDate { CivilDate.from(clock()) }
    var unit: CurrencyUnit { preferences.unit }

    func money(_ m: Money, signed: Bool = false) -> String {
        PersianFormat.money(m, unit: unit, signed: signed)
    }

    // MARK: - Refresh

    func reload() {
        do {
            ledger = try service.loadSnapshot()
            dashboard = try DashboardBuilder.build(DashboardRequest(
                ledger: ledger,
                today: today,
                horizonDays: preferences.horizonDays,
                scenario: preferences.scenario,
                reserve: preferences.reserve,
                unit: unit
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
        Task { await syncReminders() }
    }

    func syncReminders() async {
        guard let plan = try? ReminderPlanner.plan(ledger: ledger, preferences: preferences.reminders, unit: unit, now: clock()) else { return }
        await reminderScheduler.sync(plan)
    }

    /// Runs a write operation; on success refreshes everything and gives haptic feedback.
    @discardableResult
    func perform(_ successMessage: String? = nil, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            reload()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let successMessage { toast = successMessage }
            return true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Convenience lookups

    var activeAccounts: [AccountSnapshot] {
        ledger.accounts.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
    }

    var defaultAccountId: UUID? {
        activeAccounts.count == 1 ? activeAccounts.first?.id : nil
    }

    var activeCategories: [CategorySnapshot] {
        ledger.categories.filter { !$0.isArchived }
    }

    func balance(of accountId: UUID) -> Money {
        (try? FinancialCalculator.balance(of: accountId, in: ledger)) ?? .zero
    }

    func contactName(_ id: UUID?) -> String {
        ledger.contact(id)?.name ?? "—"
    }

    func lockIfNeeded() {
        if preferences.lockEnabled { isUnlocked = false }
    }

    func unlock() async {
        if await AppLock.authenticate() { isUnlocked = true }
    }

    func wipeEverything() {
        perform("همه اطلاعات حذف شد") {
            try service.wipeAll()
            attachmentStore?.deleteAll()
            try service.seedDefaultCategoriesIfNeeded()
        }
        var fresh = AppPreferences()
        fresh.onboardingCompleted = false
        preferences = fresh
        savePreferences()
        isUnlocked = true
    }
}
