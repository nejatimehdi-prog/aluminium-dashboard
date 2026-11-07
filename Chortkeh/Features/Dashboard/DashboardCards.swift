import Charts
import SwiftUI

struct HeaderView: View {
    let today: CivilDate
    let onSearch: () -> Void
    let onSettings: () -> Void
    let onReports: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("چُرتکه")
                    .font(.title.bold())
                    .foregroundStyle(Theme.gold)
                Text(PersianFormat.date(today, style: .withWeekday))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 16) {
                Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("جست‌وجو")
                    .accessibilityIdentifier("searchButton")
                Button(action: onReports) { Image(systemName: "chart.bar.doc.horizontal") }
                    .accessibilityLabel("گزارش‌ها")
                    .accessibilityIdentifier("reportsButton")
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("تنظیمات")
                    .accessibilityIdentifier("settingsButton")
            }
            .font(.title3)
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct BalanceCard: View {
    @Environment(AppState.self) private var state
    let data: DashboardData
    let onOpen: () -> Void
    let onAddAccount: () -> Void
    @State private var expanded = false

    var body: some View {
        CardContainer(title: "موجودی واقعی", symbol: "banknote", accessibilityId: "balanceCard") {
            if !data.position.hasAccounts {
                VStack(alignment: .leading, spacing: 8) {
                    Text("موجودی ثبت نشده")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("noBalanceLabel")
                    Text("یک حساب بانکی یا نقدی با موجودی واقعی امروزش بساز.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Button("افزودن حساب", action: onAddAccount)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("addFirstAccount")
                }
            } else {
                Text(state.money(data.position.cash))
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(data.position.cash.isNegative ? Theme.outflow : Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("totalCash")
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(spacing: 8) {
                        ForEach(data.accountBalances.filter { $0.account.isActive }) { row in
                            HStack {
                                Text(row.account.name)
                                Spacer()
                                AmountText(money: row.balance, unit: state.unit)
                            }
                        }
                        Button("مدیریت حساب‌ها", action: onOpen)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("\(PersianFormat.number(data.accountBalances.filter { $0.account.isActive }.count)) حساب فعال")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct ReceivablePayableCard: View {
    @Environment(AppState.self) private var state
    let position: PositionSummary
    let onOpen: () -> Void

    var body: some View {
        CardContainer(title: "طلب و بدهی", symbol: "person.2", accessibilityId: "receivablePayableCard") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("طلب‌های باز", systemImage: "arrow.down.left").font(.caption).foregroundStyle(Theme.inflow)
                    Text(state.money(position.receivables)).font(.headline.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Label("بدهی‌های باز", systemImage: "arrow.up.right").font(.caption).foregroundStyle(Theme.outflow)
                    Text(state.money(position.payables)).font(.headline.monospacedDigit())
                }
            }
            Divider()
            HStack {
                Text("خالص موقعیت ثبت‌شده")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                AmountText(money: position.netPosition, unit: state.unit)
            }
            Text("این عدد پولِ قابل خرج کردن نیست؛ فقط تصویر کلی دارایی و تعهدات ثبت‌شده است.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("اشخاص و مانده‌ها", action: onOpen)
                .font(.callout)
                .accessibilityIdentifier("openContacts")
        }
    }
}

struct SafeToSpendCard: View {
    @Environment(AppState.self) private var state
    let safe: SafeToSpend

    var body: some View {
        @Bindable var state = state
        CardContainer(title: "چقدر می‌توانم با خیال راحت خرج کنم؟", symbol: "shield.lefthalf.filled", accessibilityId: "safeToSpendCard") {
            Text(state.money(safe.amount))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(safe.amount.isNegative ? Theme.outflow : Theme.inflow)
                .accessibilityIdentifier("safeToSpendAmount")
            Picker("بازه", selection: $state.preferences.horizonDays) {
                ForEach(ForecastEngine.supportedHorizons, id: \.self) { d in
                    Text("\(PersianFormat.number(d)) روز").tag(d)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 4) {
                InfoRow(title: "موجودی نقد", value: state.money(safe.cash))
                InfoRow(title: "پرداخت‌های قطعی تا \(PersianFormat.number(safe.horizonDays)) روز", value: state.money(safe.committedOutflows), valueColor: Theme.outflow)
                if safe.reserve.isPositive {
                    InfoRow(title: "ذخیره احتیاطی", value: state.money(safe.reserve))
                }
            }
            .font(.callout)
            Text(safe.amount.isNegative
                 ? "پرداخت‌های قطعی این بازه از موجودی فعلی بیشتر است."
                 : "دریافتی‌های احتمالی در این عدد حساب نشده‌اند.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct ForecastCard: View {
    @Environment(AppState.self) private var state
    let forecast: ForecastResult
    let onOpen: () -> Void

    var body: some View {
        @Bindable var state = state
        CardContainer(title: "پیش‌بینی پول", symbol: "chart.xyaxis.line", accessibilityId: "forecastCard") {
            Picker("سناریو", selection: $state.preferences.scenario) {
                ForEach(ForecastScenario.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            ForecastChart(forecast: forecast, reserve: state.preferences.reserve, unit: state.unit)
                .frame(height: 150)

            if let shortfall = forecast.firstShortfall {
                Label {
                    Text("از \(PersianFormat.date(shortfall.date)) (\(PersianFormat.relativeDays(forecast.today.days(until: shortfall.date)))) موجودی منفی می‌شود. حداکثر کسری: \(state.money(forecast.requiredFunds)).")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                }
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier("shortfallWarning")
            } else if let breach = forecast.firstReserveBreach {
                Label("از \(PersianFormat.date(breach.date)) موجودی زیر ذخیره احتیاطی می‌رود (کمبود: \(state.money(forecast.requiredForReserve))).",
                      systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.warning)
            } else {
                Label("در این بازه کسری پیش‌بینی نمی‌شود.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.inflow)
            }
            HStack {
                InfoRow(title: "پایان بازه", value: state.money(forecast.endBalance))
            }
            .font(.callout)
            Button("جزئیات و فرض‌ها", action: onOpen)
                .font(.callout)
                .accessibilityIdentifier("forecastDetails")
        }
    }
}

struct ForecastChart: View {
    let forecast: ForecastResult
    let reserve: Money
    let unit: CurrencyUnit

    var body: some View {
        Chart {
            ForEach(forecast.days) { day in
                LineMark(
                    x: .value("روز", forecast.today.days(until: day.date)),
                    y: .value("مانده", Double(day.endBalance.rials) / Double(unit.rialsPerUnit))
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Theme.gold)
            }
            RuleMark(y: .value("صفر", 0))
                .foregroundStyle(Theme.outflow.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            if reserve.isPositive {
                RuleMark(y: .value("ذخیره", Double(reserve.rials) / Double(unit.rialsPerUnit)))
                    .foregroundStyle(Theme.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if let s = forecast.firstShortfall {
                PointMark(
                    x: .value("روز", forecast.today.days(until: s.date)),
                    y: .value("مانده", Double(s.endBalance.rials) / Double(unit.rialsPerUnit))
                )
                .foregroundStyle(Theme.outflow)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Int.self) { Text(PersianFormat.number(d)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(PersianFormat.compactMoney(Money(rials: Int64(v * Double(unit.rialsPerUnit))), unit: unit))
                    }
                }
            }
        }
        .accessibilityLabel("نمودار مانده پیش‌بینی‌شده \(PersianFormat.number(forecast.horizonDays)) روز آینده")
        .accessibilityValue(forecast.firstShortfall.map { "کسری از \(PersianFormat.date($0.date))" } ?? "بدون کسری")
    }
}

struct TodaySummaryCard: View {
    let insights: [Insight]
    let onAction: (InsightAction) -> Void

    var body: some View {
        CardContainer(title: "امروز چه خبر؟", symbol: "sun.max", accessibilityId: "todayCard") {
            if insights.isEmpty {
                Text("خبر خاصی نیست. 👌")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(insights) { insight in
                    Button {
                        onAction(insight.action)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(insight.severity))
                                .foregroundStyle(color(insight.severity))
                                .accessibilityHidden(true)
                            Text(insight.text)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func icon(_ s: InsightSeverity) -> String {
        switch s {
        case .warning: return "exclamationmark.triangle.fill"
        case .notice: return "bell.fill"
        case .info: return "info.circle"
        }
    }

    private func color(_ s: InsightSeverity) -> Color {
        switch s {
        case .warning: return Theme.warning
        case .notice: return Theme.gold
        case .info: return Theme.textSecondary
        }
    }
}

struct UpcomingDueList: View {
    @Environment(AppState.self) private var state
    let items: [DueItem]
    let onSelect: (DueItem) -> Void

    var body: some View {
        CardContainer(title: "سررسیدهای نزدیک", symbol: "calendar.badge.clock", accessibilityId: "upcomingCard") {
            if items.isEmpty {
                Text("در ۳۰ روز آینده سررسیدی ثبت نشده است.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(items.prefix(8)) { item in
                    Button { onSelect(item) } label: { DueRow(item: item) }
                        .buttonStyle(.plain)
                }
                if items.count > 8 {
                    Text("و \(PersianFormat.number(items.count - 8)) مورد دیگر")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct DueRow: View {
    @Environment(AppState.self) private var state
    let item: DueItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .chequeIssued || item.kind == .chequeReceived ? "doc.text" : "person.crop.circle")
                .foregroundStyle(item.flow == .inflow ? Theme.inflow : Theme.outflow)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.kind.title)\(item.contactName.map { " · \($0)" } ?? "")")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(PersianFormat.date(item.dueDate, style: .dayMonth)) · \(PersianFormat.relativeDays(item.daysLeft))")
                    .font(.caption)
                    .foregroundStyle(item.isOverdue ? Theme.outflow : Theme.textSecondary)
            }
            Spacer()
            AmountText(money: item.amount, unit: state.unit, flow: item.flow == .inflow ? .inflow : .outflow, font: .callout.monospacedDigit())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct MonthlyOverviewCard: View {
    @Environment(AppState.self) private var state
    let month: MonthSummary

    var body: some View {
        CardContainer(title: "خرج و درآمد \(month.title)", symbol: "calendar", accessibilityId: "monthCard") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("خرج").font(.caption).foregroundStyle(Theme.textSecondary)
                    AmountText(money: month.expense, unit: state.unit, flow: .outflow, font: .headline.monospacedDigit())
                    Text("\(month.previousTitle): \(state.money(month.previousExpense))")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("درآمد").font(.caption).foregroundStyle(Theme.textSecondary)
                    AmountText(money: month.income, unit: state.unit, flow: .inflow, font: .headline.monospacedDigit())
                    Text("\(month.previousTitle): \(state.money(month.previousIncome))")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("در \(PersianFormat.number(month.daysElapsed)) روز گذشتهٔ این ماه، \(PersianFormat.number(month.daysWithExpenseRecords)) روز هزینه ثبت شده است. روزهای بدون ثبت «بدون داده» هستند، نه «بدون هزینه».")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct RecentActivityList: View {
    @Environment(AppState.self) private var state
    let items: [ActivityItem]
    let onSelect: (ActivityItem) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        CardContainer(title: "آخرین رویدادها", symbol: "clock.arrow.circlepath", accessibilityId: "recentCard") {
            if items.isEmpty {
                Text("هنوز رویدادی ثبت نشده است.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(items) { item in
                    Button { onSelect(item) } label: { ActivityRow(item: item) }
                        .buttonStyle(.plain)
                }
                Button("همه رویدادها و جست‌وجو", action: onSeeAll)
                    .font(.callout)
            }
        }
    }
}

struct ActivityRow: View {
    @Environment(AppState.self) private var state
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(item.isReversed)
                    .lineLimit(1)
                Text("\(PersianFormat.date(item.date, style: .dayMonth)) · \(item.subtitle)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            AmountText(money: item.amount, unit: state.unit, flow: item.flow, font: .callout.monospacedDigit())
                .opacity(item.isReversed ? 0.5 : 1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isReversed ? "برگشت‌خورده یا غیرفعال" : "")
    }
}

struct QuickAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("ثبت سریع", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .foregroundStyle(Color.black.opacity(0.85))
                .background(Theme.gold, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .accessibilityIdentifier("quickAddButton")
        .accessibilityLabel("ثبت سریع")
    }
}
