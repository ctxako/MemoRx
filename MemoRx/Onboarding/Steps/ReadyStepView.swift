import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct ReadyStepView: View {
    @ObservedObject var vm: OnboardingViewModel
    let onFinish: () -> Void

    private var displayName: String {
        vm.nameTrimmed.isEmpty ? "Pharmacy Student" : vm.nameTrimmed
    }

    private var levelValue: String {
        let title = vm.selectedLevel?.title ?? ""
        return title.isEmpty ? "\u{2014}" : title
    }

    private var reminderValue: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: vm.reminderTime)
    }

    var body: some View {
        OnboardingShell(
            eyebrow: "ALL SET",
            title: "You're Ready",
            customTitle: Text("You\u{2019}re ") + Text("Ready").italic().foregroundColor(warmGold),
            bodyText: "Track XP, build your streak, and monitor your progress. Everything is editable in Settings.",
            progress: (current: 6, total: 7),
            primaryTitle: "Let\u{2019}s go!",
            primaryAction: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                // Server-side `has_completed_onboarding = true` is committed HERE, not in
                // `commitIdentity()`, so a user who bails before this step re-enters
                // onboarding on next launch instead of being silently skipped past it.
                vm.commitOnboardingFinished()
                onFinish()
            },
            backAction: vm.goBack
        ) {
            VStack(alignment: .leading, spacing: 20) {
                setupCard
                whatToExpectSection
                disclaimer
            }
        }
    }

    // MARK: - Your Setup card

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR SETUP")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(1.5)
                .foregroundColor(warmGold.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.3)

            setupRow(icon: "person.fill", label: "Display name", value: displayName)
            Divider().padding(.horizontal, 16).opacity(0.3)
            setupRow(icon: "graduationcap.fill", label: "Year of study", value: levelValue)
            Divider().padding(.horizontal, 16).opacity(0.3)
            setupRow(icon: "bell.fill", label: "Daily reminder", value: reminderValue)
        }
        .background(
            ZStack(alignment: .topLeading) {
                Color.appCardBackground
                RadialGradient(
                    gradient: Gradient(colors: [warmGold.opacity(0.12), Color.clear]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 120
                )
            }
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(warmGold.opacity(0.18), lineWidth: 1)
        )
    }

    private func setupRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(warmGold.opacity(0.85))
            }
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(.label))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(.label))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - What to expect

    private var whatToExpectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT TO EXPECT")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(1.5)
                .foregroundColor(Color.appSecondaryText)

            expectCard(icon: "sunrise.fill",   text: "First drug card drops tomorrow morning")
            expectCard(icon: "trophy.fill",    text: "Leaderboard resets every week")
            expectCard(icon: "gearshape.fill", text: "Your \u{201C}profile and data\u{201D} are always editable in Settings")
        }
    }

    private func expectCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(warmGold.opacity(0.35))
                .frame(width: 3)
                .cornerRadius(2)
                .padding(.vertical, 12)
                .padding(.leading, 12)

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(warmGold.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(warmGold.opacity(0.85))
                }

                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        Text("For educational and study purposes only.\nNot a substitute for professional medical advice.")
            .font(.system(size: 12))
            .foregroundColor(Color.appSecondaryText.opacity(0.45))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
    }
}
