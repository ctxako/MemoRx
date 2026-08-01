//
//  ContentView.swift
//  MemoRx
//
//  Created by Charles Thomas Xavier Austin III on 3/30/26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenAuth") private var hasSeenAuth = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var drugService = DrugService.shared
    @StateObject private var authStatus = AuthStatusObserver.shared
    @ObservedObject private var dailyChallenge = DailyChallengeService.shared
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var hasCompletedSplashSequence = false
    @State private var didKickOffLaunchLoads = false

    /// True while the wordmark sequence is running or drugs are still loading with an empty library.
    private var shouldShowSplashLayer: Bool {
        !hasCompletedSplashSequence ||
        (drugService.isLoading && drugService.drugs.isEmpty) ||
        !dailyChallenge.hasCompletedInitialFetch
    }

    /// Underlying app UI is mounted (possibly invisible) while we run the splash fade-out so the next screen can fade in.
    private var showDestinationUnderSplash: Bool {
        !shouldShowSplashLayer || isDismissingSplash
    }

    @AppStorage("trialBannerDismissedAt") private var trialBannerDismissedAt: Double = 0
    @State private var showPaywallFromBanner = false
    @State private var isDismissingSplash = false
    @State private var splashLayerOpacity = 1.0
    @State private var contentLayerOpacity = 0.0
    @State private var splashDismissTransitionStarted = false
    @State private var lastEnteredBackgroundAt: Date?
    @State private var subscriptionLapsed = false

    private var shouldShowTrialBanner: Bool {
        guard subscriptions.isInTrial else { return false }
        let dismissedAt = Date(timeIntervalSince1970: trialBannerDismissedAt)
        return Date().timeIntervalSince(dismissedAt) > 3600 * 8
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if showDestinationUnderSplash {
                rootContent
                    .sheet(isPresented: $showPaywallFromBanner) {
                        PaywallView()
                    }
                    .opacity(contentLayerOpacity)
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            if shouldShowTrialBanner {
                                trialBannerView(daysLeft: subscriptions.trialDaysRemaining, endDate: subscriptions.trialEndDate)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            if let message = authStatus.anonAuthFailureMessage {
                                statusBanner(
                                    icon: "wifi.exclamationmark",
                                    message: message,
                                    onRetry: { authStatus.retry() },
                                    onDismiss: { authStatus.clear() }
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            if let message = dailyChallenge.lastRefreshErrorMessage {
                                statusBanner(
                                    icon: "calendar.badge.exclamationmark",
                                    message: message,
                                    onRetry: { Task { await dailyChallenge.retry() } },
                                    onDismiss: { /* refresh succeeds on next launch / scenePhase */ }
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 12)
                    }
                    .animation(.easeInOut(duration: 0.25), value: shouldShowTrialBanner)
                    .animation(.easeInOut(duration: 0.25), value: authStatus.anonAuthFailureMessage)
                    .animation(.easeInOut(duration: 0.25), value: dailyChallenge.lastRefreshErrorMessage)
            }

            if shouldShowSplashLayer || isDismissingSplash {
                LaunchSplashView {
                    hasCompletedSplashSequence = true
                }
                .opacity(splashLayerOpacity)
                .allowsHitTesting(splashLayerOpacity > 0.01)
            }
        }
        .task {
            guard !didKickOffLaunchLoads else { return }
            didKickOffLaunchLoads = true

            async let loadDrugs: Void = DrugService.shared.loadFromSupabaseOnLaunch()
            async let loadClassQuizGuides: Void = ClassQuizGuideService.shared.loadFromSupabaseOnLaunch()
            async let loadDailyChallenge: Void = DailyChallengeService.shared.refreshFromServer()
            _ = await (loadDrugs, loadClassQuizGuides, loadDailyChallenge)
            await DailyChallengeService.shared.ensureCatalogContainsChallengeDrug()

            // If the user is signed in but the device thinks they haven't onboarded
            // (fresh install, sign-out/sign-in, or stuck mid-flow), check the server for
            // an existing profile. Returning users skip onboarding.
            if hasSeenAuth && !hasCompletedOnboarding {
                let hydrated = await UserProgressService.shared.hydrateFromServerIfNeeded()
                if hydrated {
                    hasCompletedOnboarding = true
                }
            } else if hasSeenAuth {
                // Already-onboarded users still need their XP/streak refreshed from server
                // every launch so the Growth dashboard matches the leaderboard (and any
                // admin XP adjustments / merges land without a re-sign-in).
                await UserProgressService.shared.refreshAuthoritativeProgressFromServer()
            }

            // Refresh admin-controlled `is_lifetime` on every launch so comp grants take effect
            // without a re-sign-in (previously only fetched inside the Apple sign-in handler).
            if let uid = await SupabaseManager.currentUserId() {
                let isLifetime = await SupabaseManager.fetchIsLifetime(userId: uid)
                if let isLifetime { UserDefaults.standard.set(isLifetime, forKey: "isLifetime") }
                await SubscriptionManager.shared.refreshEntitlements()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                lastEnteredBackgroundAt = Date()
            }
            if phase == .active, let t = lastEnteredBackgroundAt, Date().timeIntervalSince(t) > 300 {
                Task {
                    await DailyChallengeService.shared.refreshFromServer()
                    await DailyChallengeService.shared.ensureCatalogContainsChallengeDrug()
                    await UserProgressService.shared.refreshAuthoritativeProgressFromServer()
                }
            }
        }
        .onAppear {
            resetSplashTransitionVisuals()
        }
        .onChange(of: subscriptions.hasActiveSubscription) { wasActive, isActive in
            if wasActive && !isActive && hasCompletedOnboarding {
                subscriptionLapsed = true
            }
            if isActive {
                subscriptionLapsed = false
            }
        }
        .onChange(of: shouldShowSplashLayer) { _, newValue in
            if newValue {
                splashDismissTransitionStarted = false
                resetSplashTransitionVisuals()
                return
            }
            guard !splashDismissTransitionStarted else { return }
            splashDismissTransitionStarted = true
            runSplashDismissTransition()
        }
    }

    @State private var isRetryingDrugLoad = false

    @ViewBuilder
    private var rootContent: some View {
        if drugService.drugs.isEmpty {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 10) {
                    Text("Unable to Load Drug Library")
                        .font(theme.appFont(22, weight: .bold))
                    Text(drugService.loadErrorMessage ?? "Please restart the app and try again.")
                        .font(theme.appFont(15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if AppRuntimeConfig.cloudContentOnly {
                        Text("Cloud content mode is active.")
                            .font(theme.appFont(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        isRetryingDrugLoad = true
                        Task {
                            await DrugService.shared.loadFromSupabaseOnLaunch()
                            isRetryingDrugLoad = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRetryingDrugLoad {
                                ProgressView()
                                    .tint(.primary)
                            }
                            Text("Try Again")
                                .font(theme.appFont(15, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .memoToolbarIconChipChrome()
                    }
                    .disabled(isRetryingDrugLoad)
                    .padding(.top, 8)
                }
            }
        } else if !hasSeenAuth {
            AuthView()
        } else if !hasCompletedOnboarding {
            OnboardingView()
        } else if !subscriptions.hasActiveSubscription {
            // Mandatory gate: not presented modally, so hide the (dead) close button.
            PaywallView(subscriptionLapsed: subscriptionLapsed, isDismissable: false)
        } else {
            MainTabView()
        }
    }

    @ViewBuilder
    private func trialBannerView(daysLeft: Int, endDate: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subscriptions.hasActiveSubscription ? "checkmark.seal.fill" : "clock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
            if subscriptions.hasActiveSubscription {
                let dateLabel: String = {
                    guard let endDate else {
                        return daysLeft == 1 ? "in 1 day" : "in \(daysLeft) days"
                    }
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .none
                    return f.string(from: endDate)
                }()
                Text("Subscribed · billing begins \(dateLabel)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
            } else {
                Text(daysLeft == 1 ? "1 day left in your trial" : "\(daysLeft) days left in your trial")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
            }
            Spacer()
            if !subscriptions.hasActiveSubscription {
                Button("Upgrade") {
                    showPaywallFromBanner = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
            }
            Button {
                withAnimation { trialBannerDismissedAt = Date().timeIntervalSince1970 }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13).opacity(0.6))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0xC9 / 255.0, green: 0xB9 / 255.0, blue: 0x9A / 255.0))
        )
    }

    /// Generic status banner used for both auth failures and daily-challenge refresh failures.
    /// Both surfaces previously failed silently — this is the shared "you should know" UI.
    @ViewBuilder
    private func statusBanner(
        icon: String,
        message: String,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Try again", action: onRetry)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Button("Dismiss", action: onDismiss)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.85))
        )
    }

    private func resetSplashTransitionVisuals() {
        isDismissingSplash = false
        splashLayerOpacity = 1
        contentLayerOpacity = 0
    }

    private func runSplashDismissTransition() {
        isDismissingSplash = true
        contentLayerOpacity = 0
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.5)) {
                splashLayerOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeIn(duration: 0.5)) {
                contentLayerOpacity = 1
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            isDismissingSplash = false
        }
    }
}

private struct LaunchSplashView: View {
    private let splashTop = Color(red: 51.0 / 255.0, green: 52.0 / 255.0, blue: 57.0 / 255.0)
    private let splashBottom = Color(red: 39.0 / 255.0, green: 40.0 / 255.0, blue: 41.0 / 255.0)
    private let titleLetters = Array("MemoRx")
    /// Shown one word at a time so pacing reads clearly under the title.
    private let subtitleWords = ["Your", "daily", "dose."]
    let onSequenceFinished: () -> Void
    @State private var visibleLetterCount = 0
    @State private var visibleSubtitleWordCount = 0
    @State private var didAnimate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [splashTop, splashBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(Array(titleLetters.enumerated()), id: \.offset) { index, character in
                        Text(String(character))
                            .font(.system(size: 52, weight: .semibold, design: .serif))
                            .kerning(0.6)
                            .foregroundStyle(Color(red: 245.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0))
                            .opacity(visibleLetterCount > index ? 1 : 0)
                            .offset(x: visibleLetterCount > index ? 0 : -16)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(Array(subtitleWords.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.system(size: 30, weight: .regular, design: .serif))
                            .kerning(0.35)
                            .foregroundStyle(Color(red: 245.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0))
                            .opacity(visibleSubtitleWordCount > index ? 1 : 0)
                            .offset(x: visibleSubtitleWordCount > index ? 0 : -16)
                    }
                }
            }
        }
        .task {
            guard !didAnimate else { return }
            didAnimate = true

            for index in titleLetters.indices {
                try? await Task.sleep(nanoseconds: 95_000_000)
                withAnimation(.easeOut(duration: 0.24)) {
                    visibleLetterCount = index + 1
                }
            }

            // Brief beat after title so the subtitle doesn’t stack on the last letter.
            try? await Task.sleep(nanoseconds: 220_000_000)

            // Wait for each word’s animation before revealing the next (even rhythm).
            for index in subtitleWords.indices {
                withAnimation(.easeOut(duration: 0.3)) {
                    visibleSubtitleWordCount = index + 1
                }
                if index < subtitleWords.count - 1 {
                    try? await Task.sleep(nanoseconds: 330_000_000)
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            onSequenceFinished()
        }
    }
}

/// Pushes the drug card with ordered-library dot navigation (`DrugService.orderedDrugs`).
struct LibraryOrderedDrugHost: View {
    @State private var currentDrugId: String
    private let orderedItems: [Drug]
    private let fallbackDrug: Drug
    private let showsHomeButton: Bool

    init(initialDrug: Drug, showsHomeButton: Bool = true) {
        self.orderedItems = DrugService.orderedDrugs
        self.fallbackDrug = initialDrug
        self.showsHomeButton = showsHomeButton
        _currentDrugId = State(initialValue: initialDrug.id)
    }

    private var resolvedIndex: Int {
        if let i = orderedItems.firstIndex(where: { $0.id == currentDrugId }) {
            return i
        }
        return orderedItems.firstIndex(where: { $0.id == fallbackDrug.id }) ?? 0
    }

    private var displayDrug: Drug {
        guard orderedItems.indices.contains(resolvedIndex) else { return fallbackDrug }
        return orderedItems[resolvedIndex]
    }

    var body: some View {
        Group {
            if orderedItems.isEmpty {
                DrugCardView(
                    drug: fallbackDrug,
                    showBackButton: true,
                    isToday: false,
                    showsLibraryHomeButton: showsHomeButton
                )
            } else {
                DrugCardView(
                    drug: displayDrug,
                    showBackButton: true,
                    isToday: false,
                    libraryProgressItems: orderedItems,
                    libraryProgressIndex: resolvedIndex,
                    onLibraryProgressSelect: { newIndex in
                        guard orderedItems.indices.contains(newIndex) else { return }
                        currentDrugId = orderedItems[newIndex].id
                    },
                    showsLibraryHomeButton: showsHomeButton
                )
            }
        }
    }
}

struct SubCollectionDrugsView: View {
    @Environment(\.appTheme) private var theme
    let subCollection: SubCollection
    let drugs: [Drug]
    @ObservedObject private var progress = UserProgressService.shared

    var body: some View {
        content
            .background(SubCollectionNavigationBarChrome())
            .navigationTitle(subCollectionDisplayName(subCollection))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .onAppear { LiquidTabBarSuppression.shared.libraryStackDidPush() }
            .onDisappear { LiquidTabBarSuppression.shared.libraryStackDidPop() }
    }

    private var content: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(drugs) { drug in
                        drugRow(drug)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .drugListScrollEdgeFade()
        }
    }

    private func drugRow(_ drug: Drug) -> some View {
        NavigationLink(destination: LibraryOrderedDrugHost(initialDrug: drug)) {
            let isFlagged = progress.isDrugFlagged(drug.id)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(drug.genericName.capitalized)
                        .font(theme.appFont(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let brand = drug.brandNames.first {
                        Text(brand)
                            .font(theme.appFont(13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        progress.toggleDrugFlag(drug.id)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: isFlagged ? "flag.fill" : "flag")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFlagged ? Color.orange : Color(.tertiaryLabel))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityLabel(isFlagged ? "Unflag drug" : "Flag drug")

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(14)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Matches bar fill to `appBackground` and removes the default bottom hairline so scrolling
/// does not leave a contrasting “white line” under the sticky title.
struct SubCollectionNavigationBarChrome: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ChromeViewController {
        ChromeViewController()
    }

    func updateUIViewController(_ uiViewController: ChromeViewController, context: Context) {
        uiViewController.applyChrome()
    }

    final class ChromeViewController: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyChrome()
        }

        func applyChrome() {
            guard let nav = navigationController else { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.appBackground
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
            ]
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.compactAppearance = appearance
            nav.navigationBar.compactScrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    ContentView()
}
