import SwiftUI

struct AccountsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(state.ledger.accounts.sorted { $0.sortOrder < $1.sortOrder }) { account in
                        NavigationLink {
                            AccountDetailView(accountId: account.id)
                        } label: {
                            HStack {
                                Image(systemName: account.kind == .cash ? "banknote" : "building.columns")
                                    .foregroundStyle(Theme.gold)
                                VStack(alignment: .leading) {
                                    Text(account.name)
                                    if !account.isActive {
                                        Text("غیرفعال").font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                AmountText(money: state.balance(of: account.id), unit: state.unit)
                            }
                        }
                    }
                } footer: {
                    Text("جمع حساب‌های فعال = موجودی واقعی ثبت‌شده.")
                }
                Section {
                    Button {
                        adding = true
                    } label: {
                        Label("افزودن حساب", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addAccountButton")
                }
            }
            .sheetChrome("حساب‌ها") { dismiss() }
            .sheet(isPresented: $adding) {
                NavigationStack { AccountForm() }
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

struct AccountForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var balanceText = ""

    var body: some View {
        Form {
            TextField("نام حساب (مثلاً ملت، کیف پول)", text: $name)
                .accessibilityIdentifier("accountNameField")
            Picker("نوع", selection: $kind) {
                ForEach(AccountKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            AmountField(title: "موجودی واقعی فعلی", text: $balanceText, unit: state.unit, identifier: "accountBalanceField")
        }
        .sheetChrome("حساب جدید") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") {
                    let ok = state.perform("حساب ساخته شد") {
                        let text = balanceText.trimmingCharacters(in: .whitespaces)
                        let opening = try (text.isEmpty ? Money.zero : AmountInputParser.parse(text, unit: state.unit))
                        try state.service.addAccount(name: name, kind: kind, openingBalance: opening)
                    }
                    if ok { dismiss() }
                }
                .bold()
                .accessibilityIdentifier("saveAccountButton")
            }
        }
    }
}

struct AccountDetailView: View {
    @Environment(AppState.self) private var state
    let accountId: UUID
    @State private var adjusting = false
    @State private var actualText = ""
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        let account = state.ledger.account(accountId)
        let txs = state.ledger.transactions
            .filter { $0.fromAccountId == accountId || $0.toAccountId == accountId }
            .sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
        let reversed = FinancialCalculator.reversedTransactionIds(state.ledger)
        List {
            Section {
                InfoRow(title: "موجودی ثبت‌شده", value: state.money(state.balance(of: accountId)))
                InfoRow(title: "موجودی اولیه", value: state.money(account?.openingBalance ?? .zero))
                Button("تعدیل موجودی (با موجودی واقعی بانک)") {
                    actualText = ""
                    adjusting = true
                }
                Button("تغییر نام") {
                    newName = account?.name ?? ""
                    renaming = true
                }
                if let account {
                    Button(account.isActive ? "غیرفعال کردن" : "فعال کردن") {
                        state.perform { try state.service.setAccountActive(accountId, active: !account.isActive) }
                    }
                }
                if txs.isEmpty {
                    Button("حذف حساب", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                Text("اصلاح موجودی بعد از ثبت تراکنش فقط با «تعدیل» و یک رویداد قابل پیگیری انجام می‌شود.")
            }
            Section("گردش حساب") {
                ForEach(txs) { tx in
                    let incoming = tx.toAccountId == accountId
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tx.note.isEmpty ? tx.kind.title : tx.note)
                                .strikethrough(reversed.contains(tx.id))
                            Text("\(PersianFormat.date(tx.date)) · \(tx.kind.title)")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        AmountText(money: tx.amount, unit: state.unit, flow: incoming ? .inflow : .outflow, font: .callout.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle(account?.name ?? "حساب")
        .alert("موجودی واقعی امروز", isPresented: $adjusting) {
            TextField("مبلغ", text: $actualText).keyboardType(.numberPad)
            Button("ثبت تعدیل") {
                state.perform("تعدیل ثبت شد") {
                    let actual = try AmountInputParser.parse(actualText, unit: state.unit)
                    try state.service.adjustBalance(accountId: accountId, actual: actual, date: state.today)
                }
            }
            Button("انصراف", role: .cancel) {}
        } message: {
            Text("اختلاف با موجودی ثبت‌شده به‌صورت «تعدیل موجودی» ثبت می‌شود.")
        }
        .alert("نام جدید", isPresented: $renaming) {
            TextField("نام", text: $newName)
            Button("ذخیره") { state.perform { try state.service.renameAccount(accountId, name: newName) } }
            Button("انصراف", role: .cancel) {}
        }
        .confirmationDialog("این حساب حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { state.perform("حساب حذف شد") { try state.service.deleteAccount(accountId) } }
        }
    }
}
