import Combine
import SwiftUI

/// Hides the root `LiquidTabBar` when the Library tab’s navigation stack is pushed past the
/// drug-classes list (class drug list + drug card), when Today’s side menu is open,
/// when Today pushes a drawer destination, or when Progress shows the card editor drawer.
/// `Toolbar` visibility does not affect `safeAreaInset`, so this coordinates with `MainTabView` explicitly.
@MainActor
final class LiquidTabBarSuppression: ObservableObject {
    static let shared = LiquidTabBarSuppression()

    @Published private(set) var libraryStackDepth = 0
    @Published private(set) var todayMenuDrawerOpen = false
    @Published private(set) var todayMenuDestinationPresented = false
    @Published private(set) var todayDrugDetailPresented = false
    @Published private(set) var progressCardEditorOpen = false

    func libraryStackDidPush() {
        libraryStackDepth += 1
    }

    func libraryStackDidPop() {
        libraryStackDepth = max(0, libraryStackDepth - 1)
    }

    func setTodayMenuDrawerOpen(_ open: Bool) {
        todayMenuDrawerOpen = open
    }

    func setTodayMenuDestinationPresented(_ presented: Bool) {
        todayMenuDestinationPresented = presented
    }

    func setTodayDrugDetailPresented(_ presented: Bool) {
        todayDrugDetailPresented = presented
    }

    func setProgressCardEditorOpen(_ open: Bool) {
        progressCardEditorOpen = open
    }
}
