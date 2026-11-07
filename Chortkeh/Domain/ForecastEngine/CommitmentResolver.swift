import Foundation

enum CommitmentKind: String, Codable, Sendable {
    case chequeIssued
    case chequeReceived
    case payable
    case receivable

    var title: String {
        switch self {
        case .chequeIssued: return "چک صادره"
        case .chequeReceived: return "چک دریافتی"
        case .payable: return "بدهی"
        case .receivable: return "طلب"
        }
    }
}

/// One open future cash movement, with exactly one owner.
/// `ownerId` is the forecast owner: every currency unit of a commitment is counted once.
struct Commitment: Identifiable, Hashable, Sendable {
    var id: String { ownerId }
    /// "cheque:<uuid>" or "obligation:<uuid>"
    let ownerId: String
    let sourceId: UUID
    let kind: CommitmentKind
    let flow: CashFlowDirection
    let amount: Money
    let dueDate: CivilDate?
    let confidence: ReceiptConfidence
    let contactId: UUID?
}

/// Turns cheques and obligations into non-overlapping commitments.
///
/// Rule against double counting:
/// * An active cheque owns its own outstanding amount at its due date.
/// * An obligation owns only the part NOT covered by its active linked cheques:
///   residual = outstanding(obligation) − Σ outstanding(active linked cheques), never below zero.
/// So "debt 80 + cheque 80 for that debt" produces one 80 outflow, not 160.
enum CommitmentResolver {
    static func commitments(_ ledger: LedgerSnapshot, today: CivilDate) throws -> [Commitment] {
        var result: [Commitment] = []
        var chequeCoverage: [UUID: Money] = [:]

        for cheque in ledger.cheques {
            let out = try FinancialCalculator.outstanding(of: cheque, settlements: ledger.settlements)
            guard out.isPositive else { continue }
            if let oid = cheque.obligationId, let o = ledger.obligation(oid), !o.isCancelled {
                chequeCoverage[oid] = try (chequeCoverage[oid] ?? .zero) + out
            }
            let issued = cheque.direction == .issued
            result.append(Commitment(
                ownerId: "cheque:\(cheque.id.uuidString)",
                sourceId: cheque.id,
                kind: issued ? .chequeIssued : .chequeReceived,
                flow: issued ? .outflow : .inflow,
                amount: out,
                dueDate: cheque.dueDate,
                confidence: issued ? .confirmed : cheque.confidence,
                contactId: cheque.contactId
            ))
        }

        for o in ledger.obligations where !o.isCancelled {
            let out = try FinancialCalculator.outstanding(of: o, settlements: ledger.settlements)
            guard out.isPositive else { continue }
            let covered = chequeCoverage[o.id] ?? .zero
            let residual = try out - covered
            guard residual.isPositive else { continue }
            let payable = o.direction == .payable
            result.append(Commitment(
                ownerId: "obligation:\(o.id.uuidString)",
                sourceId: o.id,
                kind: payable ? .payable : .receivable,
                flow: payable ? .outflow : .inflow,
                amount: residual,
                dueDate: o.dueDate,
                confidence: payable ? .confirmed : o.confidence,
                contactId: o.contactId
            ))
        }

        return result.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l == r ? lhs.ownerId < rhs.ownerId : l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.ownerId < rhs.ownerId
            }
        }
    }
}
