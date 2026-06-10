import SwiftUI

struct OnboardingFeatureCard: View {
    let icon: String
    let iconColor: Color
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(.label))

            Text(detail)
                .font(.system(size: 14))
                .foregroundColor(Color.appSecondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.1), lineWidth: 1)
        )
    }
}
