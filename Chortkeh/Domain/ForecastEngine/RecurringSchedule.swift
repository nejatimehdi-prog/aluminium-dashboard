import Foundation

struct RecurringOccurrence: Hashable, Sendable {
    let rule: RecurringRuleSnapshot
    /// Stable key "<ruleId>#<index>". A real transaction confirming this occurrence stores the same key,
    /// so the occurrence is never counted twice.
    let key: String
    let index: Int
    let date: CivilDate
}

enum RecurringSchedule {
    /// Hard cap so a malformed rule can never loop forever.
    static let maxIterations = 50_000

    static func occurrenceKey(ruleId: UUID, index: Int) -> String {
        "\(ruleId.uuidString)#\(index)"
    }

    /// Date of the `index`-th occurrence (0 = start date).
    static func date(of rule: RecurringRuleSnapshot, index: Int) -> CivilDate {
        let step = max(1, rule.interval)
        switch rule.frequency {
        case .daily:
            return rule.startDate.adding(days: index * step)
        case .weekly:
            return rule.startDate.adding(days: index * step * 7)
        case .monthly:
            let anchor = rule.startDate.jalali.day
            return rule.startDate.addingJalaliMonths(index * step, anchorDay: anchor, policy: rule.monthEndPolicy)
        case .yearly:
            let anchor = rule.startDate.jalali.day
            return rule.startDate.addingJalaliMonths(index * step * 12, anchorDay: anchor, policy: rule.monthEndPolicy)
        }
    }

    /// All occurrences of `rule` dated within [from, through] (inclusive) and not after the rule's end date.
    static func occurrences(of rule: RecurringRuleSnapshot, from: CivilDate, through: CivilDate) -> [RecurringOccurrence] {
        guard rule.isActive, through >= from else { return [] }
        let last = rule.endDate.map { Swift.min($0, through) } ?? through
        var result: [RecurringOccurrence] = []
        var index = 0
        // Jump close to `from` for daily/weekly rules to avoid iterating through long histories.
        let step = max(1, rule.interval)
        switch rule.frequency {
        case .daily:
            index = max(0, rule.startDate.days(until: from) / step - 1)
        case .weekly:
            index = max(0, rule.startDate.days(until: from) / (7 * step) - 1)
        default:
            break
        }
        var iterations = 0
        while iterations < maxIterations {
            iterations += 1
            let d = date(of: rule, index: index)
            if d > last { break }
            if d >= from {
                result.append(RecurringOccurrence(rule: rule, key: occurrenceKey(ruleId: rule.id, index: index), index: index, date: d))
            }
            index += 1
        }
        return result
    }

    /// Occurrences in the window that have NOT already been confirmed by a real (non-reversed) transaction.
    static func pendingOccurrences(_ ledger: LedgerSnapshot, from: CivilDate, through: CivilDate) throws -> [RecurringOccurrence] {
        let reversed = FinancialCalculator.reversedTransactionIds(ledger)
        let confirmed = Set(ledger.transactions.compactMap { tx -> String? in
            guard !reversed.contains(tx.id), tx.kind != .reversal else { return nil }
            return tx.recurrenceKey
        })
        return ledger.recurringRules
            .flatMap { occurrences(of: $0, from: from, through: through) }
            .filter { !confirmed.contains($0.key) }
            .sorted { $0.date == $1.date ? $0.key < $1.key : $0.date < $1.date }
    }
}
