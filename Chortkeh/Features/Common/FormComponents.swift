import SwiftUI

/// Numeric amount input with live Persian thousands grouping and the unit shown next to it.
struct AmountField: View {
    let title: String
    @Binding var text: String
    let unit: CurrencyUnit
    var identifier = "amountField"

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .font(.title3.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.leading)
                .accessibilityIdentifier(identifier)
                .onChange(of: text) { _, newValue in
                    let formatted = AmountInputParser.formatForEditing(newValue)
                    if formatted != newValue { text = formatted }
                }
            Text(unit.title)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("مبلغ به \(unit.title)")
    }
}

private let persianCalendar: Calendar = {
    var c = Calendar(identifier: .persian)
    c.locale = Locale(identifier: "fa_IR")
    return c
}()

/// Jalali date picker bound to a time-zone-free `CivilDate`.
struct JalaliDateField: View {
    let title: String
    @Binding var date: CivilDate

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { date.date(hour: 12) },
                set: { date = CivilDate.from($0) }
            ),
            displayedComponents: .date
        )
        .environment(\.calendar, persianCalendar)
        .environment(\.locale, Locale(identifier: "fa_IR"))
        .accessibilityValue(PersianFormat.date(date))
    }
}

/// Optional due date with an explicit "no fixed due date" switch.
struct OptionalDueDateField: View {
    @Binding var date: CivilDate?
    let fallback: CivilDate

    var body: some View {
        Toggle("سررسید مشخص دارد", isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? (date ?? fallback) : nil }
        ))
        .accessibilityIdentifier("hasDueDateToggle")
        if date != nil {
            JalaliDateField(title: "سررسید", date: Binding(
                get: { date ?? fallback },
                set: { date = $0 }
            ))
        } else {
            Text("بدون سررسید مشخص؛ در پیش‌بینی تاریخ‌دار قرار نمی‌گیرد.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct AccountPicker: View {
    @Environment(AppState.self) private var state
    let title: String
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("انتخاب کن").tag(UUID?.none)
            ForEach(state.activeAccounts) { account in
                Text("\(account.name) (\(PersianFormat.compactMoney(state.balance(of: account.id), unit: state.unit)))")
                    .tag(Optional(account.id))
            }
        }
        .accessibilityIdentifier("accountPicker")
    }
}

struct CategoryPicker: View {
    @Environment(AppState.self) private var state
    @Binding var selection: UUID?

    var body: some View {
        Picker("دسته", selection: $selection) {
            Text("بدون دسته").tag(UUID?.none)
            ForEach(state.activeCategories) { category in
                Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
            }
        }
    }
}

/// Free-text person name with quick picks from existing contacts (exact match is reused, otherwise created).
struct ContactNameField: View {
    @Environment(AppState.self) private var state
    @Binding var name: String
    @State private var showSystemPicker = false

    var body: some View {
        HStack {
            TextField("نام شخص", text: $name)
                .textContentType(.name)
                .accessibilityIdentifier("contactField")
            Menu {
                ForEach(state.ledger.contacts) { contact in
                    Button(contact.name) { name = contact.name }
                }
                Divider()
                Button {
                    showSystemPicker = true
                } label: {
                    Label("از دفترچه تلفن", systemImage: "person.crop.circle")
                }
            } label: {
                Image(systemName: "person.2.circle")
                    .imageScale(.large)
                    .accessibilityLabel("انتخاب از اشخاص")
            }
        }
        .sheet(isPresented: $showSystemPicker) {
            SystemContactPicker { picked in
                name = picked.name
            }
            .ignoresSafeArea()
        }
    }
}

/// Small top-of-form summary used in detail sheets.
struct InfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Standard sheet chrome: RTL, navigation title, close button.
    func sheetChrome(_ title: String, onClose: @escaping () -> Void) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("بستن", action: onClose)
                        .accessibilityIdentifier("closeButton")
                }
            }
    }
}
