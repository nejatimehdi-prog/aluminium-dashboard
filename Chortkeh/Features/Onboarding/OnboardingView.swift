import SwiftUI

/// Three short, skippable steps: unit → first account + real balance → optional first item.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var step = 0
    @State private var unit: CurrencyUnit = .toman
    @State private var accountName = "حساب اصلی"
    @State private var balanceText = ""
    @State private var showQuickEntry: QuickEntryKind?

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                unitStep.tag(0)
                accountStep.tag(1)
                firstItemStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            HStack {
                Button("رد کردن") { finish() }
                    .accessibilityIdentifier("onboardingSkip")
                Spacer()
                Button(step < 2 ? "بعدی" : "شروع") { next() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboardingNext")
            }
            .padding()
        }
        .sheet(item: $showQuickEntry) { kind in
            EntryRouter(kind: kind, prefill: nil)
                .environment(state)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("چُرتکه")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.gold)
            Text("پول من، حساب من")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 32)
    }

    private var unitStep: some View {
        Form {
            Section {
                Picker("واحد پول", selection: $unit) {
                    ForEach(CurrencyUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("مبالغ را با چه واحدی وارد می‌کنی؟")
            } footer: {
                Text("بعداً از تنظیمات قابل تغییر است. محاسبات همیشه دقیق و به ریال ذخیره می‌شوند.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var accountStep: some View {
        Form {
            Section {
                TextField("نام حساب (مثلاً ملت)", text: $accountName)
                AmountField(title: "موجودی واقعی فعلی", text: $balanceText, unit: unit, identifier: "onboardingBalance")
            } header: {
                Text("اولین حساب و موجودی واقعی امروزش")
            } footer: {
                Text("اگر الان نمی‌خواهی، رد کن؛ داشبورد «موجودی ثبت نشده» نشان می‌دهد، نه صفر.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var firstItemStep: some View {
        Form {
            Section {
                Button { showQuickEntry = .chequeIssued } label: { Label("ثبت اولین چک", systemImage: "doc.text") }
                Button { showQuickEntry = .receivable } label: { Label("ثبت یک طلب", systemImage: "person.crop.circle.badge.plus") }
                Button { showQuickEntry = .payable } label: { Label("ثبت یک بدهی", systemImage: "person.crop.circle.badge.minus") }
                NavigationLink {
                    RecurringRuleForm()
                } label: {
                    Label("درآمد ثابت ماهانه", systemImage: "calendar.badge.plus")
                }
            } header: {
                Text("اختیاری")
            } footer: {
                Text("همه این‌ها بعداً هم از دکمه «+ ثبت سریع» در دسترس است.")
            }
        }
        .scrollContentBackground(.hidden)
        .wrappedInNavigation()
    }

    private func next() {
        if step == 1 { saveAccountIfNeeded() }
        if step < 2 {
            withAnimation { step += 1 }
        } else {
            finish()
        }
    }

    private func saveAccountIfNeeded() {
        state.preferences.unit = unit
        let text = balanceText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, state.ledger.accounts.isEmpty else { return }
        state.perform("حساب ساخته شد") {
            let money = try AmountInputParser.parse(text, unit: unit)
            try state.service.addAccount(name: accountName, kind: .bank, openingBalance: money)
        }
    }

    private func finish() {
        if step == 1 { saveAccountIfNeeded() }
        state.preferences.unit = unit
        state.preferences.onboardingCompleted = true
    }
}

extension View {
    func wrappedInNavigation() -> some View {
        NavigationStack { self }
    }
}
