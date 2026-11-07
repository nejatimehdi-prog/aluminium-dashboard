import SwiftUI
import UIKit

/// Visual tokens: dark navy base, soft gold accent, green for money in, muted red for money out / warnings.
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let background = dynamic(light: 0xF4F1EA, dark: 0x0B1422)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x14223A)
    static let cardBorder = dynamic(light: 0xE6DFD0, dark: 0x22324F)
    static let gold = dynamic(light: 0x9C7A2B, dark: 0xD4AF5A)
    static let inflow = dynamic(light: 0x1E7A50, dark: 0x4CC38A)
    static let outflow = dynamic(light: 0xB2443C, dark: 0xE07A70)
    static let warning = dynamic(light: 0xA86412, dark: 0xF0A848)
    static let textPrimary = dynamic(light: 0x14223A, dark: 0xF2EEE4)
    static let textSecondary = dynamic(light: 0x5D6577, dark: 0x9AA6BC)

    static let cornerRadius: CGFloat = 18
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Standard card container used across the dashboard.
struct CardContainer<Content: View>: View {
    let title: String
    var symbol: String?
    var accessibilityId: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.gold)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityId ?? title)
    }
}

/// Amount text that never relies on color alone: sign symbol + color + VoiceOver label.
struct AmountText: View {
    let money: Money
    let unit: CurrencyUnit
    var flow: ActivityFlow = .neutral
    var font: Font = .body.monospacedDigit()

    var body: some View {
        HStack(spacing: 4) {
            switch flow {
            case .inflow:
                Image(systemName: "arrow.down.left").font(.caption.bold()).foregroundStyle(Theme.inflow)
            case .outflow:
                Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(Theme.outflow)
            case .neutral:
                EmptyView()
            }
            Text(PersianFormat.money(money, unit: unit))
                .font(font)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        switch flow {
        case .inflow: return Theme.inflow
        case .outflow: return Theme.outflow
        case .neutral: return money.isNegative ? Theme.outflow : Theme.textPrimary
        }
    }

    private var accessibilityText: String {
        let amount = PersianFormat.money(money, unit: unit)
        switch flow {
        case .inflow: return "دریافت \(amount)"
        case .outflow: return "پرداخت \(amount)"
        case .neutral: return amount
        }
    }
}
