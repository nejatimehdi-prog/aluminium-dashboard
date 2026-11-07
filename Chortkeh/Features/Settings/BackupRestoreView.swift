import SwiftUI
import UniformTypeIdentifiers

/// Encrypted manual backup (Share Sheet / Files / iCloud Drive chosen by the user) and verified restore.
struct BackupRestoreView: View {
    @Environment(AppState.self) private var state
    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var backupURL: URL?
    @State private var working = false
    @State private var message: String?

    @State private var importing = false
    @State private var importedData: Data?
    @State private var restorePassword = ""
    @State private var preview: BackupPreview?
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section {
                SecureField("گذرواژه (حداقل ۸ نویسه)", text: $password)
                    .textContentType(.newPassword)
                SecureField("تکرار گذرواژه", text: $passwordRepeat)
                    .textContentType(.newPassword)
                Button(working ? "در حال ساخت…" : "ساخت فایل پشتیبان") { makeBackup() }
                    .disabled(working)
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("ذخیره در Files / iCloud Drive یا اشتراک", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("پشتیبان رمزگذاری‌شده")
            } footer: {
                Text("فایل با AES-256-GCM و کلید مشتق از گذرواژه (PBKDF2-SHA256، ۶۰۰ هزار تکرار) رمز می‌شود. گذرواژه جایی ذخیره نمی‌شود؛ اگر فراموشش کنی، بازیابی ممکن نیست.")
            }

            Section {
                Button("انتخاب فایل پشتیبان") { importing = true }
                if importedData != nil {
                    SecureField("گذرواژه فایل", text: $restorePassword)
                    Button(working ? "در حال بررسی…" : "بررسی فایل") { inspect() }
                        .disabled(working)
                }
                if let preview {
                    InfoRow(title: "تاریخ پشتیبان", value: PersianFormat.date(CivilDate.from(preview.createdAt), style: .long))
                    ForEach(preview.counts) { item in
                        InfoRow(title: item.title, value: PersianFormat.number(item.count))
                    }
                    Button("جایگزینی اطلاعات فعلی با این پشتیبان", role: .destructive) { confirmRestore = true }
                }
            } header: {
                Text("بازیابی")
            } footer: {
                Text("پیش از بازیابی، فایل کامل رمزگشایی و اعتبارسنجی می‌شود. اگر بازیابی در میانه شکست بخورد، اطلاعات فعلی دست‌نخورده می‌ماند.")
            }

            if let message {
                Section { Text(message).font(.callout) }
            }
        }
        .navigationTitle("پشتیبان")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                importedData = try? Data(contentsOf: url)
                preview = nil
                message = importedData == nil ? "خواندن فایل ممکن نشد." : "فایل انتخاب شد؛ گذرواژه را وارد کن."
            case .failure:
                message = "انتخاب فایل لغو شد."
            }
        }
        .confirmationDialog("همه اطلاعات فعلی با پشتیبان جایگزین شود؟", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("بله، بازیابی کن", role: .destructive) { restore() }
        }
    }

    private var backupService: BackupService {
        BackupService(service: state.service, attachmentStore: state.attachmentStore)
    }

    private func makeBackup() {
        guard password == passwordRepeat else {
            message = "گذرواژه و تکرار آن یکی نیستند."
            return
        }
        working = true
        defer { working = false }
        do {
            let data = try backupService.exportEncrypted(password: password, preferences: state.preferences)
            let stamp = PersianFormat.date(state.today, style: .numeric).replacingOccurrences(of: "/", with: "-")
            let ascii = AmountInputParser.normalizeDigits(stamp)
            backupURL = try ReportExporter.writeTemporary(data, name: "chortkeh-backup-\(ascii).chortkeh")
            message = "فایل پشتیبان ساخته شد. آن را در جای امن ذخیره کن."
            password = ""
            passwordRepeat = ""
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "ساخت پشتیبان انجام نشد."
        }
    }

    private func inspect() {
        guard let importedData else { return }
        working = true
        defer { working = false }
        do {
            preview = try backupService.inspect(importedData, password: restorePassword)
            message = "فایل سالم است. پیش‌نمایش را بررسی کن."
        } catch {
            preview = nil
            message = (error as? LocalizedError)?.errorDescription ?? "فایل قابل بازیابی نیست."
        }
    }

    private func restore() {
        guard let preview else { return }
        do {
            try backupService.restore(preview)
            if let prefs = preview.payload.preferences {
                var restored = prefs
                restored.onboardingCompleted = true
                state.preferences = restored
            }
            state.reload()
            message = "بازیابی کامل شد."
            self.preview = nil
            importedData = nil
            restorePassword = ""
        } catch {
            state.reload()
            message = "بازیابی انجام نشد و اطلاعات قبلی حفظ شد. (\((error as? LocalizedError)?.errorDescription ?? ""))"
        }
    }
}
