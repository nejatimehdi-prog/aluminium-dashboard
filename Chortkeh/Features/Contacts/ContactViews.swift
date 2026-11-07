import SwiftUI

struct ContactsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        let summaries = (try? FinancialCalculator.contactSummaries(state.ledger, today: state.today)) ?? []
        let needle = DashboardBuilder.normalizeForSearch(filter)
        let shown = summaries.filter { needle.isEmpty || DashboardBuilder.normalizeForSearch($0.contact.name).contains(needle) }
        NavigationStack {
            List {
                if shown.isEmpty {
                    Text("هنوز شخصی ثبت نشده است.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(shown) { s in
                    NavigationLink {
                        ContactDetailView(contactId: s.contact.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.contact.name).font(.headline)
                            HStack(spacing: 12) {
                                if s.receivable.isPositive {
                                    Label(state.money(s.receivable), systemImage: "arrow.down.left").foregroundStyle(Theme.inflow)
                                }
                                if s.payable.isPositive {
                                    Label(state.money(s.payable), systemImage: "arrow.up.right").foregroundStyle(Theme.outflow)
                                }
                                if s.overdue.isPositive {
                                    Label("معوق", systemImage: "exclamationmark.circle").foregroundStyle(Theme.warning)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .searchable(text: $filter, prompt: "جست‌وجوی نام")
            .sheetChrome("اشخاص") { dismiss() }
        }
    }
}

struct ContactDetailView: View {
    @Environment(AppState.self) private var state
    let contactId: UUID
    @State private var editing = false
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var confirmDelete = false

    var body: some View {
        let contact = state.ledger.contact(contactId)
        let summary = ((try? FinancialCalculator.contactSummaries(state.ledger, today: state.today)) ?? []).first { $0.contact.id == contactId }
        let obligations = state.ledger.obligations.filter { $0.contactId == contactId }
        let cheques = state.ledger.cheques.filter { $0.contactId == contactId }
        let txs = state.ledger.transactions.filter { $0.contactId == contactId }.sorted { $0.date > $1.date }
        List {
            Section {
                if let phone = contact?.phone, !phone.isEmpty { InfoRow(title: "تلفن", value: PersianFormat.digits(phone)) }
                InfoRow(title: "طلب باز از او", value: state.money(summary?.receivable ?? .zero), valueColor: Theme.inflow)
                InfoRow(title: "بدهی باز به او", value: state.money(summary?.payable ?? .zero), valueColor: Theme.outflow)
                if let overdue = summary?.overdue, overdue.isPositive {
                    InfoRow(title: "معوق", value: state.money(overdue), valueColor: Theme.warning)
                }
                if let due = summary?.nearestDue { InfoRow(title: "نزدیک‌ترین سررسید", value: PersianFormat.date(due)) }
                InfoRow(title: "خالص رابطه (فقط اطلاع)", value: state.money(summary?.net ?? .zero))
            } footer: {
                Text("طلب و بدهی جدا نگه داشته می‌شوند؛ تهاتر فقط با تأیید صریح خودت انجام می‌شود.")
            }
            Section("طلب/بدهی") {
                ForEach(obligations) { o in
                    NavigationLink {
                        ObligationDetailView(obligationId: o.id)
                    } label: {
                        InfoRow(title: "\(o.direction.title)\(o.isCancelled ? " (لغو)" : "")", value: state.money(o.principal))
                    }
                }
            }
            Section("چک‌ها") {
                ForEach(cheques) { c in
                    NavigationLink {
                        ChequeDetailView(chequeId: c.id)
                    } label: {
                        InfoRow(title: "\(c.direction.title) · \(PersianFormat.date(c.dueDate, style: .dayMonth))", value: state.money(c.amount))
                    }
                }
            }
            Section("دریافت و پرداخت‌ها") {
                ForEach(txs) { tx in
                    InfoRow(title: "\(tx.kind.title) · \(PersianFormat.date(tx.date, style: .dayMonth))", value: state.money(tx.amount))
                }
            }
            Section {
                Button("ویرایش") {
                    name = contact?.name ?? ""
                    phone = contact?.phone ?? ""
                    note = contact?.note ?? ""
                    editing = true
                }
                Button("حذف شخص", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(contact?.name ?? "شخص")
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextField("نام", text: $name)
                    TextField("تلفن", text: $phone).keyboardType(.phonePad)
                    TextField("توضیح", text: $note)
                }
                .sheetChrome("ویرایش شخص") { editing = false }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("ذخیره") {
                            if state.perform("ذخیره شد", { try state.service.updateContact(contactId, name: name, phone: phone, note: note) }) {
                                editing = false
                            }
                        }
                    }
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .confirmationDialog("این شخص حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { state.perform("حذف شد") { try state.service.deleteContact(contactId) } }
        } message: {
            Text("اگر طلب، بدهی، چک یا تراکنشی به این شخص وابسته باشد، حذف انجام نمی‌شود.")
        }
    }
}
