import Foundation

/// Display / input unit. Storage is always rials.
enum CurrencyUnit: String, Codable, CaseIterable, Sendable {
    case toman
    case rial

    var title: String {
        switch self {
        case .toman: return "تومان"
        case .rial: return "ریال"
        }
    }

    /// How many rials make one unit.
    var rialsPerUnit: Int64 {
        switch self {
        case .toman: return 10
        case .rial: return 1
        }
    }
}

/// Exact money value stored as an integer number of rials.
/// All arithmetic is overflow-checked and throws `DomainError.overflow` instead of wrapping.
struct Money: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rials: Int64

    init(rials: Int64) {
        self.rials = rials
    }

    static let zero = Money(rials: 0)

    /// Largest absolute value accepted for a single user-entered amount (10^16 rials = 10^15 toman).
    static let maxInputRials: Int64 = 10_000_000_000_000_000

    static func toman(_ value: Int64) throws -> Money {
        try from(value, unit: .toman)
    }

    static func from(_ value: Int64, unit: CurrencyUnit) throws -> Money {
        let (v, overflow) = value.multipliedReportingOverflow(by: unit.rialsPerUnit)
        if overflow { throw DomainError.overflow }
        return Money(rials: v)
    }

    var isZero: Bool { rials == 0 }
    var isPositive: Bool { rials > 0 }
    var isNegative: Bool { rials < 0 }

    static func + (lhs: Money, rhs: Money) throws -> Money {
        let (v, overflow) = lhs.rials.addingReportingOverflow(rhs.rials)
        if overflow { throw DomainError.overflow }
        return Money(rials: v)
    }

    static func - (lhs: Money, rhs: Money) throws -> Money {
        let (v, overflow) = lhs.rials.subtractingReportingOverflow(rhs.rials)
        if overflow { throw DomainError.overflow }
        return Money(rials: v)
    }

    func negated() throws -> Money {
        if rials == Int64.min { throw DomainError.overflow }
        return Money(rials: -rials)
    }

    /// Multiplies by `numerator / denominator`, truncating toward zero.
    func scaled(numerator: Int64, denominator: Int64) throws -> Money {
        precondition(denominator != 0)
        let (v, overflow) = rials.multipliedReportingOverflow(by: numerator)
        if overflow { throw DomainError.overflow }
        return Money(rials: v / denominator)
    }

    func abs() throws -> Money {
        try (rials < 0 ? negated() : self)
    }

    static func sum<S: Sequence>(_ values: S) throws -> Money where S.Element == Money {
        var total = Money.zero
        for v in values { total = try total + v }
        return total
    }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.rials < rhs.rials
    }

    var description: String { "\(rials) IRR" }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        rials = try c.decode(Int64.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rials)
    }
}
