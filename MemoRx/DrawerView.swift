import SwiftUI
import UIKit

struct DrawerView: View {
    @Environment(\.appTheme) private var theme
    @Binding var isOpen: Bool
    @Binding var showLeaderboard: Bool
    @Binding var showDrugRequest: Bool
    @Binding var showSettings: Bool
    @Binding var showHelpFeedback: Bool
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var progress = UserProgressService.shared

    private var drawerDisplayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return userName.capitalized
        }
        return hasCompletedOnboarding ? "Pharmacist" : userName.capitalized
    }

    private var initials: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return hasCompletedOnboarding ? "P" : "?"
        }
        return String(first).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Circle()
                    .fill(Color.appInputBackground)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(initials)
                            .font(theme.appFont(26, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                Text(drawerDisplayName)
                    .font(theme.appFont(20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("@\(progress.userID)")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(progress.currentRankDisplayTitle)
                    .font(theme.appFont(14))
                    .foregroundStyle(.secondary)

                Text("\(progress.totalXP) XP")
                    .font(theme.appFont(13))
                    .foregroundStyle(.orange)
            }
            .padding(.top, 48)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 0) {
                menuRow(icon: "gearshape.fill", iconColor: .gray, title: "Settings") {
                    showSettings = true
                }
                menuRow(icon: "trophy.fill", iconColor: .orange, title: "Leaderboard") {
                    showLeaderboard = true
                }
                menuRow(icon: "pill.fill", iconColor: .green, title: "Request a Drug") {
                    showDrugRequest = true
                }
                menuRow(icon: "questionmark.circle.fill", iconColor: .gray, title: "Help & Feedback") {
                    showHelpFeedback = true
                }
            }
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 2) {
                Text("MemoRx")
                    .font(theme.appFont(13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("v1.0")
                    .font(theme.appFont(11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func menuRow(icon: String, iconColor: Color, title: String, action: (() -> Void)? = nil) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isOpen = false
            }
            action?()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(theme.appFont(16, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}
