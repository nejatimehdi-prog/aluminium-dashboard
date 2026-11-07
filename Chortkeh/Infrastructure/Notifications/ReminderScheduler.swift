import Foundation
import UserNotifications

/// Minimal surface of UNUserNotificationCenter so the scheduler can be tested with a fake.
protocol NotificationCenterClient: AnyObject {
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

final class SystemNotificationCenter: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// Keeps pending notifications in sync with the plan: removes stale ones (settled, deleted, re-dated)
/// and adds/replaces current ones. Delivery timing is ultimately decided by iOS.
final class ReminderScheduler {
    let center: NotificationCenterClient

    init(center: NotificationCenterClient) {
        self.center = center
    }

    @discardableResult
    func sync(_ plan: [PlannedReminder]) async -> Int {
        let status = await center.authorizationStatus()
        let existing = await center.pendingIdentifiers().filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            center.removePending(identifiers: existing)
            return 0
        }
        let wanted = Set(plan.map(\.id))
        let stale = existing.filter { !wanted.contains($0) }
        if !stale.isEmpty {
            center.removePending(identifiers: stale)
        }
        var added = 0
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "chortkeh"
            let comps: DateComponents
            if reminder.repeatsDaily {
                comps = DateComponents(hour: reminder.hour, minute: reminder.minute)
            } else {
                comps = reminder.day.dateComponents(hour: reminder.hour, minute: reminder.minute)
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: reminder.repeatsDaily)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
                added += 1
            } catch {
                // A failed reminder must never break bookkeeping; it is retried on the next sync.
            }
        }
        return added
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization()) ?? false
    }
}
