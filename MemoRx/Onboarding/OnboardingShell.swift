import SwiftUI

/// Universal onboarding screen template.
///
/// Progress bar sits at the very top, above the header, so it is consistent
/// across every step. Content goes into the flexible slot between the header
/// and the pinned primary button.
struct OnboardingShell<Content: View>: View {
    let eyebrow: String?
    let title: String
    let customTitle: Text?
    let bodyText: String?
    let progress: (current: Int, total: Int)?
    let primaryTitle: String
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    let backAction: (() -> Void)?
    @ViewBuilder var content: () -> Content

    init(
        eyebrow: String? = nil,
        title: String,
        customTitle: Text? = nil,
        bodyText: String? = nil,
        progress: (current: Int, total: Int)? = nil,
        primaryTitle: String,
        primaryEnabled: Bool = true,
        primaryAction: @escaping () -> Void,
        backAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.customTitle = customTitle
        self.bodyText = bodyText
        self.progress = progress
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.backAction = backAction
        self.content = content
    }

    @EnvironmentObject private var onboardingVM: OnboardingViewModel

    var body: some View {
        ZStack(alignment: .top) {
            shellContent
            if let toast = onboardingVM.permissionToast {
                permissionToastBanner(toast)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboardingVM.permissionToast)
    }

    private var shellContent: some View {
        VStack(spacing: 0) {
            if let progress {
                OnboardingProgressBar(
                    totalSteps: progress.total,
                    currentStep: progress.current
                )
                .padding(.top, 20)
                .padding(.bottom, 20)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .tracking(1.5)
                        .foregroundColor(Color.appSecondaryText)
                        .padding(.bottom, 8)
                }

                (customTitle ?? Text(title))
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if let bodyText {
                    Text(bodyText)
                        .font(.system(size: 16))
                        .foregroundColor(Color.appSecondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, progress != nil ? 0 : 24)
            .padding(.bottom, 40)

            content()
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            navButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private let chipSize: CGFloat = 64

    @ViewBuilder
    private var navButtons: some View {
        if let backAction {
            HStack(spacing: 20) {
                navChip(systemImage: "arrow.left", action: backAction, isEnabled: true)
                    .accessibilityLabel("Back")
                navChip(systemImage: "arrow.right", action: primaryAction, isEnabled: primaryEnabled)
                    .accessibilityLabel(primaryTitle)
            }
            .padding(.bottom, 32)
        } else {
            navChip(systemImage: "arrow.right", action: primaryAction, isEnabled: primaryEnabled)
                .accessibilityLabel(primaryTitle)
                .padding(.bottom, 32)
        }
    }

    private func permissionToastBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 2)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func navChip(systemImage: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isEnabled ? Color(.label) : Color.appSecondaryText.opacity(0.4))
                .frame(width: chipSize, height: chipSize)
                .memoToolbarIconChipChrome()
                .opacity(isEnabled ? 1 : 0.5)
        }
        .disabled(!isEnabled)
    }
}
