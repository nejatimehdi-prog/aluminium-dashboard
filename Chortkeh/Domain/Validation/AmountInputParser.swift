import Foundation

/// Parses user-typed amounts. Accepts Persian (۰-۹), Arabic-Indic (٠-٩) and Latin digits
/// and the common thousands separators (٬ , ، space ' and dots used as grouping).
/// Decimals are rejected: amounts are whole tomans or rials.
enum AmountInputParser {
    /// Maps Persian and Arabic-Indic digits to ASCII; leaves everything else unchanged.
    static func normalizeDigits(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x06F0...0x06F9:
                out.append(UnicodeScalar(scalar.value - 0x06F0 + 48)!)
            case 0x0660...0x0669:
                out.append(UnicodeScalar(scalar.value - 0x0660 + 48)!)
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }

    private static let groupingCharacters: Set<Character> = [",", "٬", "،", " ", "\u{00A0}", "\u{202F}", "'", "_"]

    /// Parses an integer amount in the given unit. Throws for empty, non-numeric, decimal or oversized input.
    static func parseInteger(_ input: String) throws -> Int64 {
        let normalized = normalizeDigits(input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw DomainError.invalidAmountFormat }

        var text = String(normalized.filter { !groupingCharacters.contains($0) })
        // Dots / Persian decimal separator are accepted only when they are used as thousands grouping.
        let dotChars: Set<Character> = [".", "٫"]
        if text.contains(where: { dotChars.contains($0) }) {
            let groups = text.split(omittingEmptySubsequences: false, whereSeparator: { dotChars.contains($0) })
            guard groups.count > 1,
                  let first = groups.first, !first.isEmpty, first.count <= 3,
                  groups.dropFirst().allSatisfy({ $0.count == 3 })
            else { throw DomainError.invalidAmountFormat }
            text = groups.joined()
        }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw DomainError.invalidAmountFormat
        }
        // Avoid overflow on absurdly long strings.
        let trimmed = text.drop(while: { $0 == "0" })
        if trimmed.count > 18 { throw DomainError.amountOutOfRange }
        guard let value = Int64(text) else { throw DomainError.amountOutOfRange }
        return value
    }

    /// Parses an amount and converts it exactly to rials (toman × 10).
    static func parse(_ input: String, unit: CurrencyUnit) throws -> Money {
        let value = try parseInteger(input)
        let money = try Money.from(value, unit: unit)
        guard money.rials <= Money.maxInputRials else { throw DomainError.amountOutOfRange }
        return money
    }

    /// Validates a user-entered amount for an ordinary event (strictly positive, within range).
    static func parsePositive(_ input: String, unit: CurrencyUnit) throws -> Money {
        let money = try parse(input, unit: unit)
        guard money.isPositive else { throw DomainError.amountMustBePositive }
        return money
    }

    /// Live formatting while typing: keeps digits only and re-groups them with Persian digits.
    static func formatForEditing(_ input: String) -> String {
        let digitsOnly = normalizeDigits(input).filter { $0.isASCII && $0.isNumber }
        let stripped = String(digitsOnly.drop(while: { $0 == "0" }))
        if stripped.isEmpty { return digitsOnly.isEmpty ? "" : PersianFormat.digits("0") }
        let limited = String(stripped.prefix(17))
        guard let value = Int64(limited) else { return PersianFormat.digits(limited) }
        return PersianFormat.number(value)
    }
}
