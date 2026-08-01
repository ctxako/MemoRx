import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @AppStorage("highContrastEnabled") private var highContrastEnabled = false
    @ObservedObject private var liquidTabSuppression = LiquidTabBarSuppression.shared

    private let tabSymbols = ["sun.max.fill", "books.vertical.fill", "chart.bar.fill"]
    private let tabAccessibilityLabels = [
        "Today",
        "Library",
        "Growth — progress, spaced reviews, and your weekly leaderboard snapshot."
    ]

    /// `LiquidTabBar` uses `safeAreaInset`, not `toolbar`, so we hide it explicitly for these cases.
    private var hideLiquidTabBar: Bool {
        // Growth -> Archives also drills into `DrugCardView`, which calls `libraryStackDidPush()`.
        // Suppress the liquid tab bar for that case too so the bottom dot navigator can take its place.
        let libraryDrilledIn = (selectedTab == 1 || selectedTab == 2) && liquidTabSuppression.libraryStackDepth > 0
        let todayDrawerOpen = selectedTab == 0 && liquidTabSuppression.todayMenuDrawerOpen
        let todayMenuDestination = selectedTab == 0 && liquidTabSuppression.todayMenuDestinationPresented
        let todayDrugDetailPresented = selectedTab == 0 && liquidTabSuppression.todayDrugDetailPresented
        let progressEditorOpen = selectedTab == 2 && liquidTabSuppression.progressCardEditorOpen
        return libraryDrilledIn || todayDrawerOpen || todayMenuDestination || todayDrugDetailPresented || progressEditorOpen
    }

    var body: some View {
        ZStack {
            // Single full-bleed surface behind the tab host so there’s no UIKit “void” strip
            // between scroll content and the custom bar (Today / Library were showing pure black).
            Color.appBackground
                .ignoresSafeArea()

            ZStack {
                TodayView()
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .zIndex(selectedTab == 0 ? 1 : 0)
                    .animation(nil, value: selectedTab)
                    .allowsHitTesting(selectedTab == 0)

                LibraryView()
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .zIndex(selectedTab == 1 ? 1 : 0)
                    .animation(nil, value: selectedTab)
                    .allowsHitTesting(selectedTab == 1)

                ProgressDashboardView()
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .zIndex(selectedTab == 2 ? 1 : 0)
                    .animation(nil, value: selectedTab)
                    .allowsHitTesting(selectedTab == 2)
            }
            .background(Color.clear)
            // Depend on high-contrast setting so palette changes propagate live across tabs.
            .overlay(Color.clear.opacity(highContrastEnabled ? 0.001 : 0))
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hideLiquidTabBar {
                    VStack(spacing: 0) {
                        LiquidTabBar(
                            symbols: tabSymbols,
                            selectedIndex: $selectedTab,
                            accessibilityLabels: tabAccessibilityLabels
                        )
                            .padding(.horizontal, 40)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    // Opaque strip so scrolling lists don’t read through the glass highlight behind the tab icons.
                    .background(Color.appBackground)
                    .overlay(alignment: .top) {
                        // Gradient that bleeds upward so list content fades into the tab bar
                        // rather than hard-cutting at the safe-area edge.
                        LinearGradient(
                            colors: [.clear, Color.appBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 52)
                        .offset(y: -52)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .tint(Color(.label))
        .onChange(of: selectedTab) { _, new in
            if new != 0 {
                LiquidTabBarSuppression.shared.setTodayMenuDrawerOpen(false)
                LiquidTabBarSuppression.shared.setTodayMenuDestinationPresented(false)
                LiquidTabBarSuppression.shared.setTodayDrugDetailPresented(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTodayTab)) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLibraryTab)) { _ in
            selectedTab = 1
        }
    }
}

#Preview {
    MainTabView()
}
