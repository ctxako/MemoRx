import SwiftUI

struct OnboardingProgressBar: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(
                        i <= currentStep
                            ? Color.primary
                            : Color.appSecondaryText.opacity(0.2)
                    )
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }
}
