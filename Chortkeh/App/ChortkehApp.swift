import SwiftData
import SwiftUI

@main
struct ChortkehApp: App {
    @State private var state = AppState.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa_IR"))
                .modelContainer(state.container)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var obscured = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !state.preferences.onboardingCompleted {
                OnboardingView()
                    .transition(.opacity)
            } else if !state.isUnlocked {
                LockView()
            } else {
                DashboardView()
            }
            if obscured && state.preferences.hidePreviewInAppSwitcher {
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .tint(Theme.gold)
        .animation(.easeInOut(duration: 0.2), value: state.preferences.onboardingCompleted)
        .animation(.easeInOut(duration: 0.15), value: obscured)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                obscured = false
                state.reload()
            case .inactive:
                obscured = true
            case .background:
                obscured = true
                state.lockIfNeeded()
            @unknown default:
                break
            }
        }
        .onChange(of: state.preferences) { _, _ in
            state.savePreferences()
            state.reload()
        }
        .alert("خطا", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("باشه", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

/// Covers financial data while the app is in the App Switcher.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.gold)
                Text("چُرتکه")
                    .font(.title.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("پول من، حساب من")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityIdentifier("privacyCover")
    }
}

struct LockView: View {
    @Environment(AppState.self) private var state
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(Theme.gold)
            Text("چُرتکه قفل است")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            if failed {
                Text("احراز هویت انجام نشد. دوباره تلاش کن؛ رمز دستگاه هم پذیرفته می‌شود.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
            }
            Button {
                Task {
                    await state.unlock()
                    failed = !state.isUnlocked
                }
            } label: {
                Label("بازکردن", systemImage: "lock.open")
                    .frame(maxWidth: 240)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("unlockButton")
            Spacer()
        }
        .task {
            await state.unlock()
            failed = !state.isUnlocked
        }
    }
}
