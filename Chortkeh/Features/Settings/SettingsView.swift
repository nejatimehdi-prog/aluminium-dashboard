import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var reserveText = ""
    @State private var budgetText = ""
    @State private var confirmWipe = false
    @State private var confirmWipeAgain = false
    @State private var lockMessage: String?
    @State private var notificationText = ""

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Form {
                Section("نمایش") {
                    Picker("واحد پول", selection: $state.preferences.unit) {
                        ForEach(CurrencyUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("بازه پیش‌فرض پیش‌بینی", selection: $state.preferences.horizonDays) {
                        ForEach(ForecastEngine.supportedHorizons, id: \.self) { Text("\(PersianFormat.number($0)) روز").tag($0) }
                    }
                    Picker("سناریو", selection: $state.preferences.scenario) {
                        ForEach(ForecastScenario.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    AmountField(title: "ذخیره احتیاطی", text: $reserveText, unit: state.unit, identifier: "reserveField")
                    Button("ذخیره مبلغ احتیاطی") {
                        do {
                            let text = reserveText.trimmingCharacters(in: .whitespaces)
                            state.preferences.reserve = try (text.isEmpty ? Money.zero : AmountInputParser.parse(text, unit: state.unit))
                            state.toast = "ذخیره احتیاطی تنظیم شد"
                        } catch {
                            state.errorMessage = (error as? LocalizedError)?.errorDescription
                        }
                    }
                    AmountField(title: "بودجه ماهانه هزینه‌های متغیر", text: $budgetText, unit: state.unit, identifier: "budgetField")
                    Button("ذخیره بودجه") {
                        state.perform("بودجه ذخیره شد") {
                            let text = budgetText.trimmingCharacters(in: .whitespaces)
                            let budget: Money? = try (text.isEmpty ? nil : AmountInputParser.parse(text, unit: state.unit))
                            try state.service.setMonthlyBudget(budget)
                        }
                    }
                } header: {
                    Text("ذخیره و بودجه")
                } footer: {
                    Text("ذخیره احتیاطی مبلغی است که می‌خواهی همیشه در حساب بماند. بودجه اختیاری است و برای برآورد هزینه روزمره در پیش‌بینی استفاده می‌شود؛ خالی بگذاری، از میانگین ثبت‌های خودت استفاده می‌شود.")
                }

                Section("داده‌ها") {
                    NavigationLink("حساب‌ها") { AccountsList() }
                    NavigationLink("دسته‌های هزینه") { CategoriesView() }
                    NavigationLink("درآمد و هزینه‌های تکراری") { RecurringRulesView() }
                    NavigationLink("پشتیبان‌گیری و بازیابی") { BackupRestoreView() }
                    NavigationLink("سابقه عملیات") { AuditLogView() }
                }

                Section {
                    Toggle("یادآوری سررسیدها", isOn: $state.preferences.reminders.dueRemindersEnabled)
                    Stepper("ساعت یادآوری: \(PersianFormat.number(state.preferences.reminders.hour))",
                            value: $state.preferences.reminders.hour, in: 6...22)
                    Toggle("هشدار موارد سررسیدگذشته", isOn: $state.preferences.reminders.overdueAlerts)
                    Toggle("یادآوری روزانه ثبت هزینه", isOn: $state.preferences.reminders.dailyExpenseReminder)
                    if state.preferences.reminders.dailyExpenseReminder {
                        Stepper("ساعت یادآوری روزانه: \(PersianFormat.number(state.preferences.reminders.dailyHour))",
                                value: $state.preferences.reminders.dailyHour, in: 6...23)
                    }
                    Toggle("نمایش مبلغ و نام در اعلان", isOn: $state.preferences.reminders.showDetails)
                    Button("اجازه اعلان") {
                        Task {
                            let granted = await state.reminderScheduler.requestPermission()
                            notificationText = granted ? "اعلان‌ها فعال است." : "اجازه داده نشد؛ از تنظیمات iOS قابل تغییر است."
                            await state.syncReminders()
                        }
                    }
                    if !notificationText.isEmpty { Text(notificationText).font(.footnote) }
                } header: {
                    Text("اعلان‌ها")
                } footer: {
                    Text("پیش‌فرض: ۷، ۳ و ۱ روز قبل و روز سررسید. متن اعلان روی صفحه قفل بدون مبلغ و نام است مگر اینکه خودت فعال کنی. زمان دقیق تحویل اعلان را iOS تعیین می‌کند.")
                }

                Section {
                    Toggle("قفل با Face ID / رمز دستگاه", isOn: Binding(
                        get: { state.preferences.lockEnabled },
                        set: { enable in
                            if enable {
                                switch AppLock.availability() {
                                case .unavailable(let reason):
                                    lockMessage = reason
                                default:
                                    state.preferences.lockEnabled = true
                                    lockMessage = nil
                                }
                            } else {
                                state.preferences.lockEnabled = false
                            }
                        }
                    ))
                    if let lockMessage { Text(lockMessage).font(.footnote).foregroundStyle(Theme.warning) }
                    Toggle("پوشاندن در App Switcher", isOn: $state.preferences.hidePreviewInAppSwitcher)
                } header: {
                    Text("امنیت و حریم خصوصی")
                } footer: {
                    Text("هیچ داده‌ای بدون اقدام خودت از دستگاه خارج نمی‌شود. برنامه تبلیغات، ردیاب و سرور ندارد.")
                }

                Section {
                    Button("حذف همه اطلاعات", role: .destructive) { confirmWipe = true }
                }

                Section {
                    Text("چُرتکه — پول من، حساب من\nنسخه \(PersianFormat.digits(BackupService.appVersion))")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .sheetChrome("تنظیمات") { dismiss() }
            .onAppear {
                if state.preferences.reserve.isPositive {
                    reserveText = PersianFormat.number(state.preferences.reserve.rials / state.unit.rialsPerUnit)
                }
                if let b = state.ledger.monthlyBudget {
                    budgetText = PersianFormat.number(b.rials / state.unit.rialsPerUnit)
                }
            }
            .confirmationDialog("همه اطلاعات حذف شود؟", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("ادامه", role: .destructive) { confirmWipeAgain = true }
            } message: {
                Text("پیشنهاد می‌شود قبل از این کار پشتیبان بگیری.")
            }
            .alert("مطمئنی؟ این کار برگشت‌پذیر نیست.", isPresented: $confirmWipeAgain) {
                Button("بله، همه را حذف کن", role: .destructive) {
                    state.wipeEverything()
                    dismiss()
                }
                Button("انصراف", role: .cancel) {}
            }
        }
    }
}

private struct AccountsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List(state.ledger.accounts.sorted { $0.sortOrder < $1.sortOrder }) { account in
            NavigationLink {
                AccountDetailView(accountId: account.id)
            } label: {
                InfoRow(title: account.name + (account.isActive ? "" : " (غیرفعال)"), value: state.money(state.balance(of: account.id)))
            }
        }
        .navigationTitle("حساب‌ها")
    }
}

struct CategoriesView: View {
    @Environment(AppState.self) private var state
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(state.ledger.categories) { c in
                    HStack {
                        Label(c.name, systemImage: c.symbol)
                            .foregroundStyle(c.isArchived ? Theme.textSecondary : Theme.textPrimary)
                        Spacer()
                        Button(c.isArchived ? "فعال" : "بایگانی") {
                            state.perform { try state.service.updateCategory(c.id, name: c.name, archived: !c.isArchived) }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
            Section("دسته جدید") {
                TextField("نام دسته", text: $newName)
                Button("افزودن") {
                    if state.perform("دسته اضافه شد", { try state.service.addCategory(name: newName) }) { newName = "" }
                }
            }
        }
        .navigationTitle("دسته‌ها")
    }
}

struct AuditLogView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let events = (try? state.service.auditEvents()) ?? []
        List(events.prefix(300), id: \.id) { e in
            VStack(alignment: .leading, spacing: 2) {
                Text(e.summary)
                Text(PersianFormat.date(CivilDate.from(e.timestamp), style: .numeric))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("سابقه عملیات")
    }
}

struct RecurringRulesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let pending = (try? RecurringSchedule.pendingOccurrences(state.ledger, from: state.today.adding(days: -31), through: state.today)) ?? []
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending, id: \.key) { occ in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(occ.rule.title)
                                Text(PersianFormat.date(occ.date)).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("ثبت واقعی") {
                                state.perform("ثبت شد") {
                                    try state.service.confirmOccurrence(occ, amount: occ.rule.amount,
                                                                        accountId: occ.rule.accountId ?? state.defaultAccountId, date: occ.date)
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("موعدهای گذشته ثبت‌نشده")
                } footer: {
                    Text("وقوعی که واقعی ثبت شود دیگر در پیش‌بینی تکرار نمی‌شود.")
                }
            }
            Section {
                ForEach(state.ledger.recurringRules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.title)
                            Text("\(rule.kind.title) · \(rule.frequency.title) · از \(PersianFormat.date(rule.startDate, style: .dayMonth))")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(state.money(rule.amount)).font(.callout)
                    }
                    .opacity(rule.isActive ? 1 : 0.5)
                    .swipeActions {
                        Button(rule.isActive ? "توقف" : "فعال") {
                            state.perform { try state.service.setRecurringRuleActive(rule.id, active: !rule.isActive) }
                        }
                    }
                }
                NavigationLink("قاعده جدید") { RecurringRuleForm() }
            }
        }
        .navigationTitle("تکراری‌ها")
    }
}

struct RecurringRuleForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var title = "حقوق ماهانه"
    @State private var isIncome = true
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var start = CivilDate(dayNumber: 0)
    @State private var hasEnd = false
    @State private var end = CivilDate(dayNumber: 0)
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var policy: MonthEndPolicy = .lastValidDay

    var body: some View {
        Form {
            Picker("نوع", selection: $isIncome) {
                Text("درآمد").tag(true)
                Text("هزینه").tag(false)
            }
            .pickerStyle(.segmented)
            TextField("عنوان", text: $title)
            AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
            AccountPicker(title: "حساب", selection: $accountId)
            if !isIncome { CategoryPicker(selection: $categoryId) }
            Picker("تناوب", selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            JalaliDateField(title: "اولین موعد", date: $start)
            if frequency == .monthly || frequency == .yearly {
                Picker("اگر روز در ماه نبود", selection: $policy) {
                    ForEach(MonthEndPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Toggle("تاریخ پایان دارد", isOn: $hasEnd)
            if hasEnd { JalaliDateField(title: "پایان", date: $end) }
        }
        .navigationTitle("قاعده تکرار")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") {
                    let ok = state.perform("قاعده ذخیره شد") {
                        let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
                        try state.service.addRecurringRule(
                            title: title, kind: isIncome ? .income : .expense, amount: amount, accountId: accountId,
                            categoryId: isIncome ? nil : categoryId, startDate: start, endDate: hasEnd ? end : nil,
                            frequency: frequency, monthEndPolicy: policy
                        )
                    }
                    if ok { dismiss() }
                }
            }
        }
        .onAppear {
            if start.dayNumber == 0 {
                start = state.today
                end = state.today.adding(days: 365)
                accountId = state.defaultAccountId
                policy = state.preferences.defaultMonthEndPolicy
            }
        }
    }
}
