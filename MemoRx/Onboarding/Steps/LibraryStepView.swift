import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct LibraryStepView: View {
    @ObservedObject var vm: OnboardingViewModel

    private var progress: (current: Int, total: Int)? {
        vm.mode == .tour ? nil : (current: 3, total: 7)
    }

    var body: some View {
        OnboardingShell(
            title: "Your Library",
            customTitle: Text("Your ") + Text("Library").italic().foregroundColor(warmGold),
            bodyText: "Every drug. Your pace.",
            progress: progress,
            primaryTitle: "Next",
            primaryAction: { vm.advance() },
            backAction: vm.goBack
        ) {
            VStack(spacing: 12) {
                emojiFeatureCard(
                    emoji: "\u{1F4DA}",
                    headline: "Browse the full catalog",
                    detail: "Go deeper on any drug in the library whenever you want \u{2014} not just the drug of the day."
                )
                emojiFeatureCard(
                    emoji: "\u{1F50D}",
                    headline: "Search & filter",
                    detail: "Find drugs by class, indication, or mechanism in seconds."
                )
                sfFeatureCard(
                    icon: "flag.fill",
                    headline: "Flag for later",
                    detail: "Flag drugs you want to revisit and build your own study list."
                )
            }
        }
    }

    private func emojiFeatureCard(emoji: String, headline: String, detail: String) -> some View {
        featureCardShell(headline: headline, detail: detail) {
            Text(emoji).font(.system(size: 22))
        }
    }

    private func sfFeatureCard(icon: String, headline: String, detail: String) -> some View {
        featureCardShell(headline: headline, detail: detail) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(warmGold)
        }
    }

    private func featureCardShell<Icon: View>(
        headline: String,
        detail: String,
        @ViewBuilder iconContent: () -> Icon
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(warmGold.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                    )
                    .frame(width: 44, height: 44)
                iconContent()
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
