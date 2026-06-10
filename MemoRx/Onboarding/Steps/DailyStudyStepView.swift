import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct DailyStudyStepView: View {
    @ObservedObject var vm: OnboardingViewModel

    private var progress: (current: Int, total: Int)? {
        vm.mode == .tour ? nil : (current: 2, total: 7)
    }
    private var backAction: (() -> Void)? {
        if vm.mode == .tour { return nil }
        return { vm.goBack() }
    }

    var body: some View {
        OnboardingShell(
            title: "Daily Study",
            customTitle: Text("Daily ") + Text("Study").italic().foregroundColor(warmGold),
            bodyText: "One drug. One quiz. Every day.",
            progress: progress,
            primaryTitle: "Next",
            primaryAction: { vm.advance() },
            backAction: backAction
        ) {
            VStack(spacing: 12) {
                featureCard(
                    emoji: "\u{1F4D6}",
                    headline: "High-yield, every morning",
                    detail: "One pharmacology card and quick quiz for even the busiest rotation day."
                )
                featureCard(
                    emoji: "\u{1F310}",
                    headline: "Same drug, for everyone",
                    detail: "Universal daily drug keeps the leaderboard fair and consistent."
                )
                featureCard(
                    emoji: "\u{1F525}",
                    headline: "Show up daily",
                    detail: "Streaks and rankings reward consistency."
                )
            }
        }
    }

    private func featureCard(emoji: String, headline: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(warmGold.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                Text(emoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.label))
                Text(detail)
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
}
