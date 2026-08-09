import SwiftUI

/// Capture-mode root — replaces ContentView entirely, bypassing auth, onboarding,
/// paywall, progress, and subscription work. Drives the real DrugCardView and
/// QuizView through the scripted sequence.
struct MarketingCaptureRootView: View {
    @StateObject private var coordinator = MarketingCaptureCoordinator()

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            switch coordinator.phase {
            case .loading:
                SwiftUI.ProgressView()

            case .card:
                if let drug = coordinator.drug {
                    DrugCardView(
                        drug: drug,
                        showBackButton: false,
                        isToday: true,
                        captureAutoFlipDelay: coordinator.timing.frontHold
                    )
                }

            case .quiz, .finished:
                // Same view across both phases so the results screen holds its
                // final frame after the run is marked finished.
                if let drug = coordinator.drug, let script = coordinator.script {
                    QuizView(
                        drug: drug,
                        source: .daily,
                        captureScript: script,
                        onCaptureCompleted: { coordinator.quizDidComplete() }
                    )
                }

            case .failed(let reason):
                failureView(reason: reason)
            }

            if let status = coordinator.statusMarkerValue {
                // Marker for the Phase 2 UI-test driver; visually imperceptible
                // but present in the accessibility tree.
                Text(status)
                    .font(.system(size: 1))
                    .opacity(0.02)
                    .accessibilityIdentifier("marketingCaptureStatus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .task { await coordinator.start() }
    }

    private func failureView(reason: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.red)
            Text("Capture failed")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
            Text(reason)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
