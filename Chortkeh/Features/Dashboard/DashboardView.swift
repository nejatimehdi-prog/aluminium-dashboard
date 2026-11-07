import SwiftUI

enum DashboardSheet: Identifiable {
    case quickEntry
    case entry(QuickEntryKind, ParsedEntry?)
    case accounts
    case account(UUID)
    case contacts
    case contact(UUID)
    case obligation(UUID)
    case cheque(UUID)
    case transaction(UUID)
    case search
    case reports
    case settings
    case forecast

    var id: String {
        switch self {
        case .quickEntry: return "quick"
        case .entry(let k, _): return "entry-\(k.rawValue)"
        case .accounts: return "accounts"
        case .account(let id): return "account-\(id)"
        case .contacts: return "contacts"
        case .contact(let id): return "contact-\(id)"
        case .obligation(let id): return "obligation-\(id)"
        case .cheque(let id): return "cheque-\(id)"
        case .transaction(let id): return "tx-\(id)"
        case .search: return "search"
        case .reports: return "reports"
        case .settings: return "settings"
        case .forecast: return "forecast"
        }
    }

    /// Maps a commitment owner id ("cheque:<uuid>" / "obligation:<uuid>") to its detail sheet.
    static func forOwner(_ ownerId: String) -> DashboardSheet? {
        let parts = ownerId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "cheque": return .cheque(id)
        case "obligation": return .obligation(id)
        default: return nil
        }
    }
}

struct DashboardView: View {
    @Environment(AppState.self) private var state
    @State private var sheet: DashboardSheet?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    HeaderView(
                        today: state.today,
                        onSearch: { sheet = .search },
                        onSettings: { sheet = .settings },
                        onReports: { sheet = .reports }
                    )
                    if let data = state.dashboard {
                        BalanceCard(data: data, onOpen: { sheet = .accounts }, onAddAccount: { sheet = .accounts })
                        ReceivablePayableCard(position: data.position, onOpen: { sheet = .contacts })
                        if data.position.hasAccounts {
                            SafeToSpendCard(safe: data.safeToSpend)
                            ForecastCard(forecast: data.forecast, onOpen: { sheet = .forecast })
                        }
                        TodaySummaryCard(insights: data.insights, onAction: handle)
                        UpcomingDueList(items: data.upcoming, onSelect: { item in sheet = DashboardSheet.forOwner(item.ownerId) })
                        MonthlyOverviewCard(month: data.month)
                        RecentActivityList(items: data.recent, onSelect: open, onSeeAll: { sheet = .search })
                    }
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .refreshable { state.reload() }

            QuickAddButton { sheet = .quickEntry }
                .padding(.leading, 20)
                .padding(.bottom, 20)
        }
        .overlay(alignment: .top) { ToastView() }
        .sheet(item: $sheet) { item in
            sheetContent(item)
                .environment(state)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa_IR"))
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: DashboardSheet) -> some View {
        switch item {
        case .quickEntry:
            QuickEntrySheet { kind, prefill in
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = .entry(kind, prefill) }
            }
        case .entry(let kind, let prefill):
            EntryRouter(kind: kind, prefill: prefill)
        case .accounts:
            AccountsSheet()
        case .account(let id):
            NavigationStack { AccountDetailView(accountId: id) }
        case .contacts:
            ContactsSheet()
        case .contact(let id):
            NavigationStack { ContactDetailView(contactId: id) }
        case .obligation(let id):
            NavigationStack { ObligationDetailView(obligationId: id) }
        case .cheque(let id):
            NavigationStack { ChequeDetailView(chequeId: id) }
        case .transaction(let id):
            NavigationStack { TransactionDetailView(transactionId: id) }
        case .search:
            ActivitySearchSheet()
        case .reports:
            ReportsSheet()
        case .settings:
            SettingsView()
        case .forecast:
            ForecastDetailSheet()
        }
    }

    private func open(_ item: ActivityItem) {
        switch item.kind {
        case .transaction: sheet = .transaction(item.id)
        case .obligation: sheet = .obligation(item.id)
        case .cheque: sheet = .cheque(item.id)
        }
    }

    private func handle(_ action: InsightAction) {
        switch action {
        case .recordExpense: sheet = .entry(.expense, nil)
        case .openCommitment(let owner): sheet = DashboardSheet.forOwner(owner)
        case .openForecast: sheet = .forecast
        case .none: break
        }
    }
}

struct ToastView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let message = state.toast {
            Text(message)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation { state.toast = nil }
                }
                .accessibilityIdentifier("toast")
        }
    }
}
