import SwiftUI

/// "+ ثبت سریع": eight operations plus an optional sentence box that pre-fills a form (never saves by itself).
struct QuickEntrySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let onChoose: (QuickEntryKind, ParsedEntry?) -> Void
    @State private var sentence = ""
    @State private var parseMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(QuickEntryKind.allCases) { kind in
                            Button {
                                onChoose(kind, nil)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: kind.symbol).font(.title2)
                                    Text(kind.title).font(.callout.weight(.semibold)).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .foregroundStyle(Theme.textPrimary)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                            }
                            .accessibilityIdentifier("quickEntry.\(kind.rawValue)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("یا یک جمله بنویس")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("مثلاً: امروز ۸۵۰ هزار تومان خرید خانه از حساب ملت", text: $sentence, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("smartTextField")
                        Button("پیش‌نمایش و تکمیل فرم") { parse() }
                            .buttonStyle(.bordered)
                            .disabled(sentence.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let parseMessage {
                            Text(parseMessage).font(.footnote).foregroundStyle(Theme.warning)
                        }
                        Text("متن فقط روی همین دستگاه تحلیل می‌شود. هیچ چیزی بدون تأیید تو ذخیره نمی‌شود.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .sheetChrome("ثبت سریع") { dismiss() }
        }
        .presentationDetents([.medium, .large])
    }

    private func parse() {
        let parsed = SmartTextParser.parse(sentence, context: .init(
            today: state.today, unit: state.unit, accounts: state.activeAccounts, categories: state.activeCategories
        ))
        guard let kind = parsed.kind else {
            parseMessage = "نوع عملیات مشخص نشد؛ لطفاً یکی از گزینه‌های بالا را انتخاب کن."
            return
        }
        onChoose(kind, parsed)
    }
}

/// Picks the right form for an operation.
struct EntryRouter: View {
    let kind: QuickEntryKind
    let prefill: ParsedEntry?

    var body: some View {
        NavigationStack {
            switch kind {
            case .expense, .income:
                IncomeExpenseForm(isExpense: kind == .expense, prefill: prefill)
            case .transfer:
                TransferForm()
            case .payable, .receivable:
                ObligationForm(direction: kind == .payable ? .payable : .receivable, prefill: prefill)
            case .chequeIssued, .chequeReceived:
                ChequeForm(direction: kind == .chequeIssued ? .issued : .received, prefill: prefill)
            case .settle:
                SettlementPicker(prefill: prefill)
            }
        }
    }
}
