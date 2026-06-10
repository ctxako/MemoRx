import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct RequestStepView: View {
    @ObservedObject var vm: OnboardingViewModel

    private var progress: (current: Int, total: Int)? {
        vm.mode == .tour ? nil : (current: 4, total: 7)
    }

    var body: some View {
        OnboardingShell(
            title: "Request Drug",
            customTitle: Text("Request").italic().foregroundColor(warmGold) + Text(" Drug"),
            progress: progress,
            primaryTitle: "Next",
            primaryAction: { vm.advance() },
            backAction: vm.goBack
        ) {
            VStack(spacing: 16) {
                featureCard
                menuPreview
                    .opacity(0.85)
                    .allowsHitTesting(false)
            }
        }
    }

    private var featureCard: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(warmGold.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(warmGold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Request any drug")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.label))
                Text("Tap \u{2018}Request Drug\u{2019} from the menu. We review every submission and add approved drugs within 72 hours.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appSecondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(warmGold.opacity(0.35))
                .frame(width: 3)
                .cornerRadius(2)
                .padding(.vertical, 12)
                .padding(.leading, 12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }

    private var menuPreview: some View {
        VStack(spacing: 0) {
            previewRow(icon: "trophy.fill",              iconColor: .orange, title: "Leaderboard",    isHighlighted: false)
            Divider().opacity(0.4)
            previewRow(icon: "pill.fill",                iconColor: warmGold, title: "Request a Drug", isHighlighted: true)
            Divider().opacity(0.4)
            previewRow(icon: "questionmark.circle.fill", iconColor: .gray,   title: "Help & Feedback", isHighlighted: false)
            Divider().opacity(0.4)
            previewRow(icon: "gearshape.fill",           iconColor: .gray,   title: "Settings",        isHighlighted: false)
        }
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }

    private func previewRow(icon: String, iconColor: Color, title: String, isHighlighted: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isHighlighted ? warmGold : iconColor)
                .frame(width: 20, height: 20)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isHighlighted ? warmGold : Color(.label))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.appSecondaryText.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(isHighlighted ? warmGold.opacity(0.07) : Color.clear)
    }
}
