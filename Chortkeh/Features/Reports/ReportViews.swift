import SwiftUI

struct ActivitySearchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind: ActivityKind?
    @State private var selected: ActivityItem?

    var body: some View {
        let all = DashboardBuilder.activities(state.ledger)
        let results = DashboardBuilder.search(all, text: text, kind: kind, from: nil, through: nil)
        NavigationStack {
            List {
                Picker("نوع", selection: $kind) {
                    Text("همه").tag(ActivityKind?.none)
                    ForEach(ActivityKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                if results.isEmpty {
                    Text("موردی پیدا نشد.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(results) { item in
                    Button { selected = item } label: { ActivityRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $text, prompt: "نام، توضیح، مبلغ…")
            .sheetChrome("رویدادها") { dismiss() }
            .navigationDestination(item: $selected) { item in
                switch item.kind {
                case .transaction: TransactionDetailView(transactionId: item.id)
                case .obligation: ObligationDetailView(obligationId: item.id)
                case .cheque: ChequeDetailView(chequeId: item.id)
                }
            }
        }
    }
}

struct TransactionDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let transactionId: UUID
    @State private var confirmReverse = false
    @State private var editing = false

    var body: some View {
        let tx = state.ledger.transaction(transactionId)
        let reversed = FinancialCalculator.reversedTransactionIds(state.ledger).contains(transactionId)
        List {
            if let tx {
                Section {
                    InfoRow(title: "نوع", value: tx.kind.title)
                    InfoRow(title: "مبلغ", value: state.money(tx.amount))
                    InfoRow(title: "تاریخ", value: PersianFormat.date(tx.date, style: .withWeekday))
                    if let a = state.ledger.account(tx.fromAccountId) { InfoRow(title: "از حساب", value: a.name) }
                    if let a = state.ledger.account(tx.toAccountId) { InfoRow(title: "به حساب", value: a.name) }
                    if let c = state.ledger.contact(tx.contactId) { InfoRow(title: "شخص", value: c.name) }
                    if let c = state.ledger.category(tx.categoryId) { InfoRow(title: "دسته", value: c.name) }
                    if !tx.note.isEmpty { InfoRow(title: "توضیح", value: tx.note) }
                    if reversed { InfoRow(title: "وضعیت", value: "برگشت‌خورده", valueColor: Theme.outflow) }
                    if let original = state.ledger.transaction(tx.reversesTransactionId) {
                        InfoRow(title: "برگشتِ", value: "\(original.kind.title) \(PersianFormat.date(original.date))")
                    }
                }
                if !reversed && tx.kind != .reversal {
                    Section {
                        if tx.kind == .income || tx.kind == .expense {
                            Button("اصلاح") { editing = true }
                        }
                        Button("برگشت / حذف", role: .destructive) { confirmReverse = true }
                            .accessibilityIdentifier("reverseTransaction")
                    } footer: {
                        Text("برای حفظ سابقه، حذف و اصلاح با یک رویداد برگشت ثبت می‌شود و مانده‌ها خودکار درست می‌شوند.")
                    }
                }
            } else {
                Text("تراکنش پیدا نشد.")
            }
        }
        .navigationTitle("جزئیات تراکنش")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("این تراکنش برگشت بخورد؟", isPresented: $confirmReverse, titleVisibility: .visible) {
            Button("برگشت بزن", role: .destructive) {
                if state.perform("برگشت ثبت شد", { try state.service.reverseTransaction(transactionId) }) { dismiss() }
            }
        } message: {
            Text("اگر این تراکنش بابت تسویه طلب، بدهی یا چک بوده، آن مورد دوباره باز می‌شود.")
        }
        .sheet(isPresented: $editing) {
            if let tx {
                NavigationStack { CorrectTransactionForm(original: tx) }
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

struct CorrectTransactionForm: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let original: TransactionSnapshot
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = CivilDate(dayNumber: 0)
    @State private var categoryId: UUID?
    @State private var note = ""

    var body: some View {
        Form {
            AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
            AccountPicker(title: "حساب", selection: $accountId)
            JalaliDateField(title: "تاریخ", date: $date)
            if original.kind == .expense { CategoryPicker(selection: $categoryId) }
            TextField("توضیح", text: $note)
        }
        .sheetChrome("اصلاح تراکنش") { dismiss() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") {
                    let ok = state.perform("اصلاح ثبت شد") {
                        let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
                        try state.service.correctTransaction(original.id, amount: amount, accountId: accountId, date: date,
                                                             categoryId: categoryId, note: note)
                    }
                    if ok { dismiss() }
                }
            }
        }
        .onAppear {
            amountText = PersianFormat.number(original.amount.rials / state.unit.rialsPerUnit)
            accountId = original.fromAccountId ?? original.toAccountId
            date = original.date
            categoryId = original.categoryId
            note = original.note
        }
    }
}

struct ForecastDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let f = state.dashboard?.forecast {
                List {
                    Section {
                        ForecastChart(forecast: f, reserve: state.preferences.reserve, unit: state.unit).frame(height: 200)
                        InfoRow(title: "موجودی شروع", value: state.money(f.startBalance))
                        InfoRow(title: "کمترین مانده", value: f.minimumDay.map { "\(state.money($0.endBalance)) (\(PersianFormat.date($0.date, style: .dayMonth)))" } ?? "—")
                        InfoRow(title: "نخستین روز کسری", value: f.firstShortfall.map { PersianFormat.date($0.date) } ?? "ندارد",
                                valueColor: f.hasShortfall ? Theme.outflow : Theme.inflow)
                        InfoRow(title: "وجه موردنیاز برای منفی‌نشدن", value: state.money(f.requiredFunds))
                        InfoRow(title: "مانده پایان بازه", value: state.money(f.endBalance))
                    }
                    Section("فرض‌ها") {
                        ForEach(f.assumptions, id: \.self) { Text($0).font(.callout) }
                    }
                    if !f.undated.isEmpty {
                        Section("تعهدات بی‌موعد (در پیش‌بینی نیامده)") {
                            ForEach(f.undated) { c in
                                InfoRow(title: "\(c.kind.title) · \(state.contactName(c.contactId))", value: state.money(c.amount))
                            }
                        }
                    }
                    Section("رویدادهای روزبه‌روز") {
                        ForEach(f.days.filter { !$0.inflow.isZero || !$0.outflow.isZero }) { day in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(PersianFormat.date(day.date, style: .dayMonth)).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(state.money(day.endBalance))
                                        .foregroundStyle(day.endBalance.isNegative ? Theme.outflow : Theme.textPrimary)
                                        .font(.callout.monospacedDigit())
                                }
                                HStack {
                                    if day.inflow.isPositive { Text("ورود \(state.money(day.inflow))").foregroundStyle(Theme.inflow) }
                                    if day.outflow.isPositive { Text("خروج \(state.money(day.outflow))").foregroundStyle(Theme.outflow) }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .sheetChrome("پیش‌بینی پول") { dismiss() }
            } else {
                Text("داده‌ای برای پیش‌بینی نیست.").sheetChrome("پیش‌بینی پول") { dismiss() }
            }
        }
    }
}

struct ReportsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        let today = state.today
        let monthStart = today.startOfJalaliMonth
        let totals = try? FinancialCalculator.periodTotals(state.ledger, from: monthStart, through: today)
        let todayTotals = try? FinancialCalculator.periodTotals(state.ledger, from: today, through: today)
        let summaries = ((try? FinancialCalculator.contactSummaries(state.ledger, today: today)) ?? [])
            .filter { $0.receivable.isPositive || $0.payable.isPositive }
        let next7 = (try? DashboardBuilder.dueItems(state.ledger, today: today, withinDays: 7))?.filter { $0.flow == .outflow } ?? []
        NavigationStack {
            List {
                Section("خلاصه") {
                    InfoRow(title: "خرج امروز", value: state.money(todayTotals?.expense ?? .zero))
                    InfoRow(title: "خرج \(PersianFormat.monthTitle(today))", value: state.money(totals?.expense ?? .zero))
                    InfoRow(title: "درآمد \(PersianFormat.monthTitle(today))", value: state.money(totals?.income ?? .zero))
                    InfoRow(title: "جمع طلب‌ها", value: state.money(state.dashboard?.position.receivables ?? .zero))
                    InfoRow(title: "جمع بدهی‌ها", value: state.money(state.dashboard?.position.payables ?? .zero))
                    InfoRow(title: "پرداخت‌های ۷ روز آینده", value: state.money((try? Money.sum(next7.map(\.amount))) ?? .zero))
                    if let s = state.dashboard?.forecast.firstShortfall {
                        InfoRow(title: "نخستین روز احتمال کسری", value: PersianFormat.date(s.date), valueColor: Theme.outflow)
                    }
                }
                if let byCategory = totals?.expenseByCategory, !byCategory.isEmpty {
                    Section("خرج این ماه به تفکیک دسته") {
                        ForEach(byCategory.sorted { $0.value > $1.value }, id: \.key) { entry in
                            InfoRow(title: state.ledger.category(entry.key)?.name ?? "بدون دسته", value: state.money(entry.value))
                        }
                    }
                }
                if !summaries.isEmpty {
                    Section("اشخاص با بیشترین مانده") {
                        ForEach(summaries.prefix(10)) { s in
                            InfoRow(title: s.contact.name, value: "طلب \(state.money(s.receivable)) / بدهی \(state.money(s.payable))")
                                .font(.callout)
                        }
                    }
                }
                Section {
                    Button { export(.transactionsCSV) } label: { Label("خروجی تراکنش‌ها (CSV)", systemImage: "tablecells") }
                    Button { export(.commitmentsCSV) } label: { Label("خروجی طلب/بدهی/چک‌ها (CSV)", systemImage: "list.bullet.rectangle") }
                    Button { export(.pdf) } label: { Label("گزارش PDF", systemImage: "doc.richtext") }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("اشتراک‌گذاری فایل ساخته‌شده", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let exportError { Text(exportError).foregroundStyle(Theme.outflow) }
                } header: {
                    Text("خروجی")
                } footer: {
                    Text("فایل فقط با انتخاب خودت از طریق برگه اشتراک‌گذاری از دستگاه خارج می‌شود.")
                }
            }
            .sheetChrome("گزارش‌ها") { dismiss() }
        }
    }

    private enum ExportKind { case transactionsCSV, commitmentsCSV, pdf }

    private func export(_ kind: ExportKind) {
        do {
            let stamp = PersianFormat.date(state.today, style: .numeric).replacingOccurrences(of: "/", with: "-")
            switch kind {
            case .transactionsCSV:
                let csv = ReportExporter.transactionsCSV(state.ledger, unit: state.unit)
                exportURL = try ReportExporter.writeTemporary(Data(csv.utf8), name: "chortkeh-transactions-\(stamp).csv")
            case .commitmentsCSV:
                let csv = ReportExporter.commitmentsCSV(state.ledger, today: state.today, unit: state.unit)
                exportURL = try ReportExporter.writeTemporary(Data(csv.utf8), name: "chortkeh-commitments-\(stamp).csv")
            case .pdf:
                guard let data = state.dashboard else { return }
                let pdf = try ReportExporter.pdf(data: data, ledger: state.ledger, unit: state.unit)
                exportURL = try ReportExporter.writeTemporary(pdf, name: "chortkeh-report-\(stamp).pdf")
            }
            exportError = nil
        } catch {
            exportError = (error as? LocalizedError)?.errorDescription ?? "ساخت فایل انجام نشد."
        }
    }
}
