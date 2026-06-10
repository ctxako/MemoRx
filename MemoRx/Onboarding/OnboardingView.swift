import SwiftUI
import UIKit

// MARK: - Student Level

enum StudentLevel: String, CaseIterable {
    case prePharm = "pre-pharm"
    case p1 = "p1"
    case p2 = "p2"
    case p3 = "p3"
    case p4 = "p4"
    case graduate = "graduate"
    case other = "other"

    var displayLabel: String {
        switch self {
        case .prePharm: return "Pre-Pharmacy"
        case .p1: return "P1"
        case .p2: return "P2"
        case .p3: return "P3"
        case .p4: return "P4"
        case .graduate: return "Graduate"
        case .other: return "Other"
        }
    }

    var tag: String {
        switch self {
        case .prePharm: return "Foundation"
        case .p1: return "Year 1"
        case .p2: return "Year 2"
        case .p3: return "Year 3"
        case .p4: return "Year 4"
        case .graduate: return "Advanced"
        case .other: return "Other"
        }
    }

    /// Display title stored in studentLevelTitle UserDefaults key.
    var title: String {
        switch self {
        case .prePharm: return "Pre-Pharm"
        case .p1: return "P1"
        case .p2: return "P2"
        case .p3: return "P3"
        case .p4: return "P4"
        case .graduate: return "Graduate"
        case .other: return ""
        }
    }
}

// MARK: - OnboardingView (Router)

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var vm: OnboardingViewModel
    private let onTourFinish: (() -> Void)?
    @State private var showPaywall = false
    @ObservedObject private var subscriptions = SubscriptionManager.shared

    init(mode: OnboardingMode = .onboarding, onTourFinish: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: OnboardingViewModel(mode: mode))
        self.onTourFinish = onTourFinish
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            Group {
                switch vm.step {
                case 1:
                    IdentityStepView(vm: vm)
                case 2:
                    GoalStepView(vm: vm)
                case 3:
                    DailyStudyStepView(vm: vm)
                case 4:
                    LibraryStepView(vm: vm)
                case 5:
                    RequestStepView(vm: vm)
                case 6:
                    ReminderStepView(vm: vm)
                default:
                    ReadyStepView(vm: vm) {
                        if vm.mode == .onboarding && !subscriptions.hasActiveSubscription {
                            showPaywall = true
                        } else {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: vm.isGoingBack ? .leading : .trailing),
                removal: .move(edge: vm.isGoingBack ? .trailing : .leading)
            ))
        }
        .environmentObject(vm)
        .onChange(of: vm.step) { _, newStep in
            if vm.mode == .tour && newStep >= 6 {
                onTourFinish?()
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: subscriptions.hasActiveSubscription) { _, isActive in
            if isActive && showPaywall {
                showPaywall = false
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    OnboardingView()
}
