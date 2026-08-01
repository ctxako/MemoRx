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
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            Group {
                switch vm.step {
                case 1:
                    WelcomeChallengeStepView(vm: vm)
                case 2:
                    ResultGapStepView(vm: vm)
                case 3:
                    GoalStepView(vm: vm)
                default:
                    // Step 4 — notifications is the final onboarding screen. It owns the
                    // finish hook that ReadyStepView used to carry (ReadyStepView removed in Pass 1).
                    ReminderStepView(vm: vm) {
                        // Persist the name fallback, "member since" startDate, and profile
                        // sync that the (removed) Identity screen used to write. Name/year
                        // capture moves onto GoalStepView in Pass 2; commitIdentity() stays for that.
                        vm.commitIdentity()
                        // Finish unconditionally. Monetization is owned by ContentView's
                        // paywall gate on the next render, so a non-subscriber who closes
                        // the paywall can't get trapped re-running onboarding.
                        vm.commitOnboardingFinished()
                        hasCompletedOnboarding = true
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: vm.isGoingBack ? .leading : .trailing),
                removal: .move(edge: vm.isGoingBack ? .trailing : .leading)
            ))
        }
        .environmentObject(vm)
    }
}

#Preview {
    OnboardingView()
}
