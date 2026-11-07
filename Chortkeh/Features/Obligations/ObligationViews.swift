import SwiftUI

struct ObligationDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let obligationId: UUID
    @State private var editingDue = false
    @State private var newDue: CivilDate?
    @State private var confirmCancel = false

    private var obligation: ObligationSnapshot? { state.ledger.obligation(obligationId) }

    var body: some View {
        Group {
            if let o = obligation {
                content(o)
            } else {
                Text("این مورد پیدا نشد.")
            }
        }
        .sheetChrome(obligation?.direction == .receivable ? "طلب" : "بدهی") { dismiss() }
    }

    @ViewBuilder
    private func content(_ o: ObligationSnapshot) -> some View {
        let settlements = state.ledger.settlements.filter { $0.obligationId == o.id }
        let outstanding = (try? FinancialCalculator.outstanding(of: o, settlements: state.ledger.settlements)) ?? .zero
        let linkedCheques = state.ledger.cheques.filter { $0.obligationId == o.id }
        List {
            Section {
                InfoRow(title: "شخص", value: state.contactName(o.contactId))
                InfoRow(title: "مبلغ اصلی", value: state.money(o.principal))
                InfoRow(title: "مانده باز", value: state.money(outstanding),
                        valueColor: o.direction == .receivable ? Theme.inflow : Theme.outflow)
                InfoRow(title: "سررسید", value: o.dueDate.map { "\(PersianFormat.date($0)) (\(PersianFormat.relativeDays(state.today.days(until: $0))))" } ?? "بدون سررسید مشخص")
                if o.direction == .receivable {
                    InfoRow(title: "احتمال وصول", value: o.confidence.title)
                }
                if o.isCancelled { InfoRow(title: "وضعیت", value: "لغوشده", valueColor: Theme.outflow) }
                if !o.note.isEmpty { Text(o.note).foregroundStyle(Theme.textSecondary) }
            }

            if !o.isCancelled && outstanding.isPositive {
                Section {
                    NavigationLink {
                        SettleObligationView(obligationId: o.id, onDone: {})
                    } label: {
                        Label(o.direction == .receivable ? "ثبت وصول (کامل یا جزئی)" : "ثبت پرداخت (کامل یا جزئی)", systemImage: "checkmark.seal")
                    }
                    .accessibilityIdentifier("settleObligation")
                    NavigationLink {
                        OffsetView(obligation: o)
                    } label: {
                        Label("تهاتر با \(o.direction == .receivable ? "بدهی" : "طلب") همین شخص", systemImage: "arrow.triangle.swap")
                    }
                    Button {
                        newDue = o.dueDate ?? state.today
                        editingDue = true
                    } label: {
                        Label("تغییر سررسید", systemImage: "calendar")
                    }
                }
            }

            if !linkedCheques.isEmpty {
                Section("چک‌های مرتبط") {
                    ForEach(linkedCheques) { c in
                        NavigationLink {
                            ChequeDetailView(chequeId: c.id)
                        } label: {
                            InfoRow(title: "\(c.direction.title) · \(PersianFormat.date(c.dueDate, style: .dayMonth))", value: state.money(c.amount))
                        }
                    }
                }
            }

            Section("تاریخچه تسویه") {
                if settlements.isEmpty {
                    Text("هنوز تسویه‌ای ثبت نشده.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(settlements) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.method == .offset ? "تهاتر" : "نقدی")
                            Text(PersianFormat.date(s.date)).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(state.money(s.amount))
                            .strikethrough(s.isVoided)
                            .foregroundStyle(s.isVoided ? Theme.textSecondary : Theme.textPrimary)
                    }
                    .swipeActions {
                        if !s.isVoided {
                            if s.method == .offset {
                                Button("لغو تهاتر") {
                                    state.perform("تهاتر لغو شد") { try state.service.voidOffset(groupId: s.groupId) }
                                }
                            } else if let tx = s.transactionId {
                                Button("برگشت") {
                                    state.perform("برگشت ثبت شد") { try state.service.reverseTransaction(tx, reason: "برگشت تسویه") }
                                }
                            }
                        }
                    }
                }
            }

            if !o.isCancelled && settlements.allSatisfy(\.isVoided) {
                Section {
                    Button("لغو این \(o.direction.title)", role: .destructive) { confirmCancel = true }
                }
            }
        }
        .sheet(isPresented: $editingDue) {
            NavigationStack {
                Form {
                    OptionalDueDateField(date: $newDue, fallback: state.today)
                }
                .sheetChrome("تغییر سررسید") { editingDue = false }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("ذخیره") {
                            if state.perform("سررسید تغییر کرد", {
                                try state.service.updateObligation(o.id, dueDate: newDue, confidence: o.confidence, note: o.note)
                            }) { editingDue = false }
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .presentationDetents([.medium])
        }
        .confirmationDialog("این مورد لغو شود؟", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("لغو کن", role: .destructive) {
                state.perform("لغو شد") { try state.service.cancelObligation(o.id) }
            }
        } message: {
            Text("رکورد حذف نمی‌شود و در تاریخچه باقی می‌ماند.")
        }
    }
}

struct SettleObligationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let obligationId: UUID
    let onDone: () -> Void
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = CivilDate(dayNumber: 0)
    @State private var confirm = false

    var body: some View {
        let o = state.ledger.obligation(obligationId)
        let outstanding = o.flatMap { try? FinancialCalculator.outstanding(of: $0, settlements: state.ledger.settlements) } ?? .zero
        let incoming = o?.direction == .receivable
        Form {
            Section {
                InfoRow(title: "شخص", value: state.contactName(o?.contactId))
                InfoRow(title: "مانده فعلی", value: state.money(outstanding))
                AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
                Button("کل مانده") {
                    amountText = PersianFormat.number(outstanding.rials / state.unit.rialsPerUnit)
                }
                .font(.callout)
                AccountPicker(title: incoming ? "به حساب" : "از حساب", selection: $accountId)
                JalaliDateField(title: "تاریخ", date: $date)
            } footer: {
                Text("مبلغ نمی‌تواند از مانده بیشتر باشد.")
            }
        }
        .navigationTitle(incoming ? "ثبت وصول" : "ثبت پرداخت")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تأیید") { confirm = true }
                    .bold()
                    .accessibilityIdentifier("confirmSettle")
            }
        }
        .confirmationDialog("ثبت شود؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("بله، ثبت کن") { save() }
        } message: {
            Text("\(incoming ? "وصول" : "پرداخت") \(amountText) \(state.unit.title) — \(state.contactName(o?.contactId))")
        }
        .onAppear {
            if date.dayNumber == 0 { date = state.today }
            if accountId == nil { accountId = state.defaultAccountId }
        }
    }

    private func save() {
        let ok = state.perform("تسویه ثبت شد") {
            let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
            try state.service.settleObligation(obligationId, amount: amount, accountId: accountId, date: date)
        }
        if ok {
            onDone()
            dismiss()
        }
    }
}

/// Explicit, confirmed offset between a receivable and a payable of the same person.
struct OffsetView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let obligation: ObligationSnapshot
    @State private var counterpartId: UUID?
    @State private var amountText = ""
    @State private var confirm = false

    private var counterparts: [ObligationSnapshot] {
        state.ledger.obligations.filter { o in
            o.contactId == obligation.contactId && o.direction != obligation.direction && !o.isCancelled
                && ((try? FinancialCalculator.outstanding(of: o, settlements: state.ledger.settlements))?.isPositive ?? false)
        }
    }

    var body: some View {
        Form {
            if counterparts.isEmpty {
                Text("این شخص \(obligation.direction == .receivable ? "بدهی" : "طلب") بازی ندارد.")
            } else {
                Picker("مقابل", selection: $counterpartId) {
                    Text("انتخاب کن").tag(UUID?.none)
                    ForEach(counterparts) { o in
                        let out = (try? FinancialCalculator.outstanding(of: o, settlements: state.ledger.settlements)) ?? .zero
                        Text("\(o.direction.title) — مانده \(state.money(out))").tag(Optional(o.id))
                    }
                }
                AmountField(title: "مبلغ تهاتر", text: $amountText, unit: state.unit)
                Text("تهاتر هیچ پولی جابه‌جا نمی‌کند و فقط مانده دو طرف را به یک اندازه کم می‌کند.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("تهاتر")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تأیید") { confirm = true }.disabled(counterpartId == nil)
            }
        }
        .confirmationDialog("تهاتر انجام شود؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("بله، تهاتر کن") {
                let ok = state.perform("تهاتر ثبت شد") {
                    guard let other = counterpartId else { throw DomainError.invalidOffset }
                    let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
                    let receivable = obligation.direction == .receivable ? obligation.id : other
                    let payable = obligation.direction == .payable ? obligation.id : other
                    try state.service.offsetObligations(receivableId: receivable, payableId: payable, amount: amount, date: state.today)
                }
                if ok { dismiss() }
            }
        }
    }
}
