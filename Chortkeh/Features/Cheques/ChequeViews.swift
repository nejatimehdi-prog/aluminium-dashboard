import PhotosUI
import SwiftUI

struct ChequeDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let chequeId: UUID
    @State private var confirmBounce = false
    @State private var confirmCancel = false
    @State private var rescheduling = false
    @State private var newDue = CivilDate(dayNumber: 0)
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showImage = false

    private var cheque: ChequeSnapshot? { state.ledger.cheque(chequeId) }

    var body: some View {
        Group {
            if let c = cheque {
                content(c)
            } else {
                Text("چک پیدا نشد.")
            }
        }
        .sheetChrome(cheque?.direction.title ?? "چک") { dismiss() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attach(item) }
        }
        .task { loadImage() }
    }

    @ViewBuilder
    private func content(_ c: ChequeSnapshot) -> some View {
        let status = (try? FinancialCalculator.status(of: c, settlements: state.ledger.settlements, today: state.today)) ?? .open
        let outstanding = (try? FinancialCalculator.outstanding(of: c, settlements: state.ledger.settlements)) ?? .zero
        let settlements = state.ledger.settlements.filter { $0.chequeId == c.id }
        List {
            Section {
                InfoRow(title: "طرف حساب", value: state.contactName(c.contactId))
                InfoRow(title: "مبلغ", value: state.money(c.amount))
                InfoRow(title: "مانده باز", value: state.money(outstanding))
                InfoRow(title: "سررسید", value: "\(PersianFormat.date(c.dueDate)) (\(PersianFormat.relativeDays(state.today.days(until: c.dueDate))))")
                InfoRow(title: "وضعیت", value: status.title,
                        valueColor: [.overdue, .bounced].contains(status) ? Theme.outflow : Theme.textPrimary)
                if !c.bankName.isEmpty { InfoRow(title: "بانک", value: c.bankName) }
                if !c.chequeNumber.isEmpty { InfoRow(title: "شماره چک", value: PersianFormat.digits(c.chequeNumber)) }
                if !c.sayadId.isEmpty { InfoRow(title: "شناسه صیادی", value: PersianFormat.digits(c.sayadId)) }
                if let o = state.ledger.obligation(c.obligationId) {
                    NavigationLink {
                        ObligationDetailView(obligationId: o.id)
                    } label: {
                        InfoRow(title: "بابت", value: "\(o.direction.title) \(state.contactName(o.contactId))")
                    }
                }
                if !c.note.isEmpty { Text(c.note).foregroundStyle(Theme.textSecondary) }
            }

            if c.lifecycle == .active {
                Section {
                    if outstanding.isPositive {
                        NavigationLink {
                            SettleChequeView(chequeId: c.id, onDone: {})
                        } label: {
                            Label(c.direction == .issued ? "ثبت پرداخت چک" : "ثبت وصول چک", systemImage: "checkmark.seal")
                        }
                        .accessibilityIdentifier("settleCheque")
                        Button {
                            newDue = c.dueDate
                            rescheduling = true
                        } label: {
                            Label("تمدید سررسید", systemImage: "calendar.badge.clock")
                        }
                    }
                    Button(role: .destructive) { confirmBounce = true } label: {
                        Label("برگشت خورد", systemImage: "arrow.uturn.backward.circle")
                    }
                    if settlements.allSatisfy(\.isVoided) {
                        Button(role: .destructive) { confirmCancel = true } label: {
                            Label("باطل/عودت", systemImage: "xmark.circle")
                        }
                    }
                }
            }

            Section("تصویر چک") {
                if image != nil {
                    Button { showImage = true } label: { Label("نمایش تصویر", systemImage: "photo") }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(image == nil ? "افزودن تصویر" : "جایگزینی تصویر", systemImage: "camera")
                }
                Text("تصویر رمزگذاری‌شده فقط روی همین دستگاه ذخیره می‌شود.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            Section("تاریخچه") {
                if settlements.isEmpty {
                    Text("پرداخت/وصولی ثبت نشده.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(settlements) { s in
                    HStack {
                        Text(PersianFormat.date(s.date))
                        Spacer()
                        Text(state.money(s.amount))
                            .strikethrough(s.isVoided)
                    }
                    .swipeActions {
                        if !s.isVoided, let tx = s.transactionId {
                            Button("برگشت") {
                                state.perform("برگشت ثبت شد") { try state.service.reverseTransaction(tx, reason: "برگشت وصول/پرداخت چک") }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("چک برگشت خورده است؟", isPresented: $confirmBounce, titleVisibility: .visible) {
            Button("بله، برگشت خورد", role: .destructive) {
                state.perform("وضعیت چک: برگشتی") { try state.service.bounceCheque(c.id, date: state.today) }
            }
        } message: {
            Text("هر وصول/پرداخت ثبت‌شده این چک با رویداد برگشت جبران می‌شود و تعهد مرتبط دوباره باز می‌شود.")
        }
        .confirmationDialog("وضعیت چک", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("باطل شد", role: .destructive) {
                state.perform("چک باطل شد") { try state.service.setChequeLifecycle(c.id, .cancelled) }
            }
            Button("عودت داده شد") {
                state.perform("چک عودت شد") { try state.service.setChequeLifecycle(c.id, .returned) }
            }
        }
        .sheet(isPresented: $rescheduling) {
            NavigationStack {
                Form { JalaliDateField(title: "سررسید جدید", date: $newDue) }
                    .sheetChrome("تمدید سررسید") { rescheduling = false }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("ذخیره") {
                                if state.perform("سررسید تمدید شد", { try state.service.rescheduleCheque(c.id, newDueDate: newDue) }) {
                                    rescheduling = false
                                }
                            }
                        }
                    }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showImage) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding()
            }
        }
    }

    private func loadImage() {
        guard let attachmentId = try? state.service.chequeAttachmentId(chequeId),
              let attachment = try? state.service.attachments().first(where: { $0.id == attachmentId }),
              let data = try? state.attachmentStore?.load(fileName: attachment.fileName)
        else { return }
        image = UIImage(data: data)
    }

    private func attach(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data),
              let jpeg = picked.jpegData(compressionQuality: 0.7),
              let store = state.attachmentStore
        else {
            state.errorMessage = "افزودن تصویر انجام نشد."
            return
        }
        let fileName = UUID().uuidString + ".bin"
        state.perform("تصویر ذخیره شد") {
            try store.save(jpeg, fileName: fileName)
            let id = try state.service.addAttachment(ownerId: chequeId, fileName: fileName)
            try state.service.setChequeAttachment(chequeId, attachmentId: id)
        }
        image = picked
    }
}

struct SettleChequeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let chequeId: UUID
    let onDone: () -> Void
    @State private var amountText = ""
    @State private var accountId: UUID?
    @State private var date = CivilDate(dayNumber: 0)
    @State private var confirm = false

    var body: some View {
        let c = state.ledger.cheque(chequeId)
        let outstanding = c.flatMap { try? FinancialCalculator.outstanding(of: $0, settlements: state.ledger.settlements) } ?? .zero
        let incoming = c?.direction == .received
        Form {
            Section {
                InfoRow(title: "چک", value: "\(c?.direction.title ?? "") · \(state.contactName(c?.contactId))")
                InfoRow(title: "سررسید", value: c.map { PersianFormat.date($0.dueDate) } ?? "")
                InfoRow(title: "مانده", value: state.money(outstanding))
                AmountField(title: "مبلغ", text: $amountText, unit: state.unit)
                AccountPicker(title: incoming ? "واریز به حساب" : "برداشت از حساب", selection: $accountId)
                JalaliDateField(title: "تاریخ واقعی", date: $date)
            } footer: {
                Text("فقط یک تراکنش نقدی ثبت می‌شود و اگر چک بابت طلب/بدهی باشد، مانده آن هم به همین اندازه کم می‌شود.")
            }
        }
        .navigationTitle(incoming ? "وصول چک" : "پرداخت چک")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("تأیید") { confirm = true }.bold()
                    .accessibilityIdentifier("confirmSettle")
            }
        }
        .confirmationDialog("ثبت شود؟", isPresented: $confirm, titleVisibility: .visible) {
            Button("بله، ثبت کن") { save() }
        } message: {
            Text("\(incoming ? "وصول" : "پرداخت") \(amountText) \(state.unit.title)")
        }
        .onAppear {
            if date.dayNumber == 0 { date = state.today }
            if amountText.isEmpty { amountText = PersianFormat.number(outstanding.rials / state.unit.rialsPerUnit) }
            if accountId == nil { accountId = c?.accountId ?? state.defaultAccountId }
        }
    }

    private func save() {
        let ok = state.perform("چک تسویه شد") {
            let amount = try AmountInputParser.parsePositive(amountText, unit: state.unit)
            try state.service.settleCheque(chequeId, amount: amount, accountId: accountId, date: date)
        }
        if ok {
            onDone()
            dismiss()
        }
    }
}
