import SwiftUI

// MARK: - Library toolbar pills (quiz curator + flag)

/// Matches `LibraryView`’s leading/trailing toolbar capsules (`quizCuratorButton`, `flaggedFilterButton`).
enum MemoToolbarPillMetrics {
    static let iconPointSize: CGFloat = 13
    static let iconWeight: Font.Weight = .semibold
    static var iconFont: Font { .system(size: iconPointSize, weight: iconWeight) }

    static let horizontalPadding: CGFloat = 11
    static let verticalPadding: CGFloat = 8

    /// Single-icon toolbar slot (width and height). **Use this square frame on the label before
    /// `memoToolbarIconChipChrome()`** so the capsule clips to a **circle** and matches Today’s menu
    /// chip (`TodayView.todayMenuToolbarButton`). Padding-only sizing yields a short pill and reads
    /// smaller/weaker than the nav bar chips.
    static let chipSlotWidth: CGFloat = horizontalPadding * 2 + 18
}

enum TabContentMetrics {
    /// Vertical inset between the iOS nav bar and the first content card.
    /// Applied uniformly on Today, Library, and Growth so card tops align.
    static let firstCardTopInset: CGFloat = 28
}

// MARK: - “Liquid” capsule chrome (matches `LiquidTabBar` highlight)

extension View {
    /// Standard top-bar pill used by toolbar controls across tabs.
    func topBarPillChrome() -> some View {
        background(Color.appCardBackground)
            .clipShape(Capsule())
    }

    /// Toolbar / onboarding icon chips: native **Liquid Glass** (`glassEffect(_:in:)`) on iOS 26 when the MemoRx target defines **`MEMORX_LIQUID_GLASS`** in Swift Active Compilation Conditions (requires Xcode with iOS 26 SwiftUI). Otherwise opaque capsule (`appCardBackground`).
    func memoToolbarIconChipChrome() -> some View {
        modifier(MemoToolbarIconChipChromeModifier())
    }

    /// `DrugCardView` Quiz CTA: **`MEMORX_LIQUID_GLASS` + iOS 26+** uses `glassEffect` (like toolbar chips); otherwise **`ultraThinMaterial`** + 0.5pt white hairline (`opacity(0.1)`), matching `memoGlassCapsuleLegacyBackground` but in a **`RoundedRectangle`** of `cornerRadius`.
    func memoQuizCTAGlassChrome(cornerRadius: CGFloat) -> some View {
        modifier(MemoRoundedRectGlassChromeModifier(cornerRadius: cornerRadius))
    }

    /// Today tab pre-reveal drug card (`DrugCardView` front face when `isToday`): same **`MEMORX_LIQUID_GLASS` / `glassEffect`** + legacy material treatment as toolbar chips, in a **`RoundedRectangle`** of `cornerRadius`.
    func memoTodayPreRevealDrugCardGlassChrome(cornerRadius: CGFloat) -> some View {
        modifier(MemoRoundedRectGlassChromeModifier(cornerRadius: cornerRadius))
    }

    /// Capsule background using the same material + edge treatment as `LiquidTabBar`’s sliding highlight (`ultraThinMaterial` + hairline stroke), or Liquid Glass when `MEMORX_LIQUID_GLASS` is set and running on iOS 26+.
    func memoGlassCapsuleChrome() -> some View {
        modifier(MemoGlassCapsuleChromeModifier())
    }
}

private struct MemoToolbarIconChipChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
#if MEMORX_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content
                .background(Color.appCardBackground)
                .clipShape(Capsule(style: .continuous))
        }
#else
        content
            .background(Color.appCardBackground)
            .clipShape(Capsule(style: .continuous))
#endif
    }
}

private struct MemoRoundedRectGlassChromeModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
#if MEMORX_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            memoRoundedRectGlassLegacyBackground(content: content)
        }
#else
        memoRoundedRectGlassLegacyBackground(content: content)
#endif
    }

    @ViewBuilder
    private func memoRoundedRectGlassLegacyBackground(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}

private struct MemoGlassCapsuleChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
#if MEMORX_LIQUID_GLASS
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            memoGlassCapsuleLegacyBackground(content: content)
        }
#else
        memoGlassCapsuleLegacyBackground(content: content)
#endif
    }

    @ViewBuilder
    private func memoGlassCapsuleLegacyBackground(content: Content) -> some View {
        content.background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }
}
