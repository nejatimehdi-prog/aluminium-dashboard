import SwiftUI

struct IncomeExpenseForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let isExpense: Bool
    let prefill: ParsedEntry?

    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = CivilDate(dayNumber: 0)
    @State private var categoryId: UUID?
    @State private var note = ""
    @State private var contactName = ""
    @State private var initialized = false

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
                AccountPicker(title: isExpense ? "از حساب" : "به حساب", selection: $accountId)
                if state.activeAccounts.isEmpty {
                    Text("اول یک حساب بساز (تنظیمات › حساب‌ها یا کارت موجودی).")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
            }
            Section("اختیاری") {
                JalaliDateField(title: "تاریخ", date: $date)
                if isExpense { CategoryPicker(selection: $categoryId) }
                TextField("توضیح", text: $note)
                ContactNameField(name: $contactName)
            }
        }
        .sheetChrome(isExpense ? "هزینه کردم" : "درآمد گرفتم") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت") { save() }
                    .bold()
                    .accessibilityIdentifier("saveButton")
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard !initialized else { return }
        initialized = true
        date = prefill?.date ?? state.today
        accountId = prefill?.accountId ?? state.defaultAccountId
        categoryId = prefill?.categoryId
        if let amount = prefill?.amount {
            amountText = PersianFormat.number(amount.rials / state.unit.rialsPerUnit)
        }
        if let p = prefill { note = p.note }
        contactName = prefill?.contactName ?? ""
    }

    private func save() {
        let ok = state.perform(isExpense ? "هزینه ثبت شد" : "درآمد ثبت شد") {
            let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
            let contactId: UUID? = try (contactName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : state.service.contactId(named: contactName))
            if isExpense {
                try state.service.recordExpense(amount: amount, accountId: accountId, date: date, categoryId: categoryId,
                                                contactId: contactId, note: note)
            } else {
                try state.service.recordIncome(amount: amount, accountId: accountId, date: date, contactId: contactId, note: note)
            }
        }
        if ok { dismiss() }
    }
}

struct TransferForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var fromId: UUID?
    @State private var toId: UUID?
    @State private var date = CivilDate(dayNumber: 0)
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
                AccountPicker(title: "از حساب", selection: $fromId)
                AccountPicker(title: "به حساب", selection: $toId)
            } footer: {
                Text("انتقال داخلی جمع موجودی را تغییر نمی‌دهد و درآمد یا هزینه حساب نمی‌شود.")
            }
            Section("اختیاری") {
                JalaliDateField(title: "تاریخ", date: $date)
                TextField("توضیح", text: $note)
            }
        }
        .sheetChrome("انتقال بین حساب‌ها") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت") {
                    let ok = state.perform("انتقال ثبت شد") {
                        let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
                        try state.service.transfer(amount: amount, from: fromId, to: toId, date: date, note: note)
                    }
                    if ok { dismiss() }
                }
                .bold()
                .accessibilityIdentifier("saveButton")
            }
        }
        .onAppear { if date.dayNumber == 0 { date = state.today } }
    }
}

struct ObligationForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let direction: ObligationDirection
    let prefill: ParsedEntry?

    @State private var amountText = ""
    @State private var contactName = ""
    @State private var dueDate: CivilDate?
    @State private var confidence: ReceiptConfidence = .expected
    @State private var note = ""
    @State private var initialized = false

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
                ContactNameField(name: $contactName)
                OptionalDueDateField(date: $dueDate, fallback: state.today.adding(days: 30))
            } footer: {
                Text(direction == .receivable
                     ? "ثبت طلب، موجودی نقد را تغییر نمی‌دهد؛ فقط وصول واقعی آن را تغییر می‌دهد."
                     : "ثبت بدهی، موجودی نقد را تغییر نمی‌دهد؛ فقط پرداخت واقعی آن را تغییر می‌دهد.")
            }
            Section("اختیاری") {
                if direction == .receivable {
                    Picker("احتمال وصول", selection: $confidence) {
                        ForEach(ReceiptConfidence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                TextField("توضیح", text: $note)
            }
        }
        .sheetChrome(direction == .receivable ? "طلبکار شدم" : "بدهکار شدم") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت") { save() }
                    .bold()
                    .accessibilityIdentifier("saveButton")
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let amount = prefill?.amount { amountText = PersianFormat.number(amount.rials / state.unit.rialsPerUnit) }
            contactName = prefill?.contactName ?? ""
            dueDate = prefill?.date
            if let p = prefill { note = p.note }
        }
    }

    private func save() {
        let ok = state.perform(direction == .receivable ? "طلب ثبت شد" : "بدهی ثبت شد") {
            let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
            let contactId = try state.service.contactId(named: contactName)
            try state.service.createObligation(direction: direction, contactId: contactId, amount: amount, dueDate: dueDate,
                                               confidence: direction == .payable ? .confirmed : confidence, note: note)
        }
        if ok { dismiss() }
    }
}

struct ChequeForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let direction: ChequeDirection
    let prefill: ParsedEntry?

    @State private var amountText = ""
    @State private var contactName = ""
    @State private var dueDate = CivilDate(dayNumber: 0)
    @State private var linkMode = LinkMode.none
    @State private var linkedObligationId: UUID?
    @State private var bankName = ""
    @State private var chequeNumber = ""
    @State private var sayadId = ""
    @State private var accountId: UUID?
    @State private var confidence: ReceiptConfidence = .expected
    @State private var note = ""
    @State private var initialized = false

    enum LinkMode: String, CaseIterable, Identifiable {
        case none, existing, createNew
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "مستقل"
            case .existing: return "بابت تعهد موجود"
            case .createNew: return "ثبت تعهد همراه"
            }
        }
    }

    private var matchingObligations: [ObligationSnapshot] {
        let wanted: ObligationDirection = direction == .issued ? .payable : .receivable
        let name = contactName.trimmingCharacters(in: .whitespaces)
        return state.ledger.obligations.filter { o in
            guard o.direction == wanted, !o.isCancelled else { return false }
            let out = (try? FinancialCalculator.outstanding(of: o, settlements: state.ledger.settlements)) ?? .zero
            return out.isPositive && (name.isEmpty || state.contactName(o.contactId) == name)
        }
    }

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ چک", text: $amountText, unit: state.unit)
                ContactNameField(name: $contactName)
                JalaliDateField(title: "سررسید", date: $dueDate)
            } footer: {
                Text("ثبت چک به‌تنهایی موجودی نقد را تغییر نمی‌دهد؛ فقط پرداخت یا وصول واقعی آن را تغییر می‌دهد.")
            }
            Section {
                Picker("ارتباط با طلب/بدهی", selection: $linkMode) {
                    ForEach(LinkMode.allCases) { Text($0.title).tag($0) }
                }
                if linkMode == .existing {
                    if matchingObligations.isEmpty {
                        Text("تعهد بازی برای این شخص پیدا نشد.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    } else {
                        Picker("تعهد", selection: $linkedObligationId) {
                            Text("انتخاب کن").tag(UUID?.none)
                            ForEach(matchingObligations) { o in
                                Text("\(state.contactName(o.contactId)) — \(state.money(o.principal))").tag(Optional(o.id))
                            }
                        }
                    }
                }
            } footer: {
                Text("اگر چک بابت یک طلب/بدهی است، فقط یک بار در پیش‌بینی حساب می‌شود.")
            }
            Section("اختیاری") {
                TextField("بانک", text: $bankName)
                TextField("شماره چک", text: $chequeNumber).keyboardType(.numberPad)
                TextField("شناسه صیادی", text: $sayadId).keyboardType(.numberPad)
                AccountPicker(title: direction == .issued ? "حساب پرداخت" : "حساب واریز", selection: $accountId)
                if direction == .received {
                    Picker("احتمال وصول", selection: $confidence) {
                        ForEach(ReceiptConfidence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                TextField("توضیح", text: $note)
            }
        }
        .sheetChrome(direction == .issued ? "چک دادم" : "چک گرفتم") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت") { save() }
                    .bold()
                    .accessibilityIdentifier("saveButton")
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            dueDate = prefill?.date ?? state.today.adding(days: 30)
            if let amount = prefill?.amount { amountText = PersianFormat.number(amount.rials / state.unit.rialsPerUnit) }
            contactName = prefill?.contactName ?? ""
            accountId = prefill?.accountId
            if let p = prefill { note = p.note }
        }
    }

    private func save() {
        let ok = state.perform(direction == .issued ? "چک صادره ثبت شد" : "چک دریافتی ثبت شد") {
            let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
            let contactId = try state.service.contactId(named: contactName)
            var obligationId: UUID?
            switch linkMode {
            case .none:
                obligationId = nil
            case .existing:
                guard let selected = linkedObligationId else { throw DomainError.notFound }
                obligationId = selected
            case .createNew:
                obligationId = try state.service.createObligation(
                    direction: direction == .issued ? .payable : .receivable, contactId: contactId, amount: amount,
                    dueDate: dueDate, confidence: direction == .issued ? .confirmed : confidence, note: note
                )
            }
            try state.service.createCheque(
                direction: direction, amount: amount, dueDate: dueDate, contactId: contactId, bankName: bankName,
                accountId: accountId, chequeNumber: chequeNumber, sayadId: sayadId, obligationId: obligationId,
                confidence: direction == .issued ? .confirmed : confidence, note: note
            )
        }
        if ok { dismiss() }
    }
}

/// Settlement entry point: choose the exact open cheque or obligation first (avoids settling the wrong one).
struct SettlementPicker: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let prefill: ParsedEntry?
    @State private var filter = ""

    private var items: [DueItem] {
        let all = (try? CommitmentResolver.commitments(state.ledger, today: state.today)) ?? []
        let needle = DashboardBuilder.normalizeForSearch(filter)
        return all.compactMap { c -> DueItem? in
            let name = state.ledger.contact(c.contactId)?.name
            if !needle.isEmpty && !DashboardBuilder.normalizeForSearch(name ?? "").contains(needle) { return nil }
            return DueItem(ownerId: c.ownerId, sourceId: c.sourceId, kind: c.kind, flow: c.flow, amount: c.amount,
                           dueDate: c.dueDate ?? state.today, daysLeft: c.dueDate.map { state.today.days(until: $0) } ?? 0,
                           contactName: name)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("مورد بازی برای تسویه وجود ندارد.").foregroundStyle(Theme.textSecondary)
            }
            ForEach(items) { item in
                NavigationLink {
                    if item.kind == .chequeIssued || item.kind == .chequeReceived {
                        SettleChequeView(chequeId: item.sourceId, onDone: { dismiss() })
                    } else {
                        SettleObligationView(obligationId: item.sourceId, onDone: { dismiss() })
                    }
                } label: {
                    DueRow(item: item)
                }
            }
        }
        .searchable(text: $filter, prompt: "نام شخص")
        .sheetChrome("کدام را تسویه می‌کنی؟") { dismiss() }
        .onAppear {
            if let name = prefill?.contactName { filter = name }
        }
    }
}
