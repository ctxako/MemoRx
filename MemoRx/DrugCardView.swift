import SwiftUI
import UIKit

private enum DrugCardDetailTheme {
    static let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
    static let sectionSurface = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
    static let sectionStroke = Color.white.opacity(0.07)
    static let whyMattersFill = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.07)
    static let whyMattersStroke = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.20)
    static let indicationBullet = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.50)
}

struct DrugCardView: View {
    private enum Layout {
        static let screenPadding: CGFloat = 20
        static let frontCardCornerRadius: CGFloat = 28
        static let sectionCornerRadius: CGFloat = 16
        static let frontCardInternalPadding: CGFloat = 32
        /// Today tab: tighter insets to match Growth hero plate feel (`GrowthHeroPlateModifier` uses 22).
        static let todayFrontCardInternalPadding: CGFloat = 22
        static let frontCardWidthFactor: CGFloat = 0.85
        static let sectionInternalPadding: CGFloat = 16
        static let contentSpacing: CGFloat = 16
        static let titleToBrandSpacing: CGFloat = 6
        static let badgeToTitleSpacing: CGFloat = 20
        static let brandToDividerSpacing: CGFloat = 28
        static let dividerToHintSpacing: CGFloat = 20
        static let sectionTitleToContentSpacing: CGFloat = 10
        static let bulletRowSpacing: CGFloat = 8
        static let iconSize: CGFloat = 6
        static let quizButtonHeight: CGFloat = 56
        static let quizButtonCornerRadius: CGFloat = 16
        static let whyItMattersBarWidth: CGFloat = 3
        /// Depth fade: outgoing face leaves first; incoming follows after a short stagger.
        static let cardDepthFadeOutDuration: Double = 0.22
        static let cardDepthFadeInDuration: Double = 0.26
        static let cardDepthFadeInStagger: Double = 0.03
    }

    let drug: Drug
    var showBackButton: Bool = true
    var isToday: Bool = false
    /// Library-only: ordered list + index for bottom `DrugProgressIndicator`; omit in Today / search.
    var libraryProgressItems: [Drug]? = nil
    var libraryProgressIndex: Int? = nil
    var onLibraryProgressSelect: ((Int) -> Void)? = nil
    /// Library detail header includes a "house" pop-to-root button by default. Growth → Archives
    /// pushes a single drug onto Growth's stack, so back and home are the same — hide home there.
    var showsLibraryHomeButton: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var progress = UserProgressService.shared
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var isFlipped = false
    @State private var hintOpacity = 1.0
    @State private var showQuiz = false
    @State private var showPaywall = false
    @State private var navigationController: UINavigationController?
    @AppStorage("selectedTheme") private var selectedThemeRaw = AppTheme.standard.rawValue
    private var theme: AppTheme {
        return AppTheme(rawValue: selectedThemeRaw) ?? .standard
    }
    /// Library detail: hide tab bar while scrolling long back-of-card content.
    @State private var hideTabBarWhileScrollingDetail = false

    /// Today + library drug detail: immersive full-bleed (tab bar hidden). Library back: still hide while scrolling detail if we ever show tab again.
    private var shouldHideTabBar: Bool {
        if isToday { return true }
        if showBackButton && !isToday { return true }
        guard isFlipped else { return false }
        return hideTabBarWhileScrollingDetail
    }

    private var isLibraryDetail: Bool {
        showBackButton && !isToday
    }

    private var showsQuizButton: Bool {
        isToday || isLibraryDetail
    }

    private var showsLibraryProgressIndicator: Bool {
        guard !isToday,
              let items = libraryProgressItems,
              let idx = libraryProgressIndex,
              !items.isEmpty,
              items.indices.contains(idx)
        else { return false }
        return onLibraryProgressSelect != nil
    }

    /// Drug card copy: black on light surfaces, white / dimmed white on dark card surfaces.
    private var detailPrimary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var detailTertiary: Color {
        colorScheme == .dark ? Color.white.opacity(0.52) : Color(white: 0.67)
    }

    private var defaultBulletIconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color.appTertiaryText
    }

    /// Body copy on fixed `#1a1a1c` section surfaces (readable in light and dark schemes).
    private var sectionContentForeground: Color {
        colorScheme == .dark ? Color.appPrimaryText : Color.white
    }

    /// Muted section headers on `#1a1a1c` — slightly brighter than `appSecondaryText` / prior white opacity for legibility.
    private var sectionHeadingMuted: Color {
        colorScheme == .dark
            ? Color(red: 182 / 255, green: 183 / 255, blue: 185 / 255)
            : Color.white.opacity(0.64)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.appBackground
                .ignoresSafeArea()

            ZStack {
                frontView
                    .opacity(isFlipped ? 0 : 1)
                    .blur(radius: isFlipped ? 6 : 0)
                    .scaleEffect(isFlipped ? 0.98 : 1.0)
                    .animation(
                        isFlipped
                            ? .easeInOut(duration: Layout.cardDepthFadeOutDuration)
                            : .easeInOut(duration: Layout.cardDepthFadeInDuration)
                                .delay(Layout.cardDepthFadeInStagger),
                        value: isFlipped
                    )
                    .allowsHitTesting(!isFlipped)

                backView
                    .opacity(isFlipped ? 1 : 0)
                    .blur(radius: isFlipped ? 0 : 6)
                    .scaleEffect(isFlipped ? 1.0 : 0.98)
                    .animation(
                        isFlipped
                            ? .easeInOut(duration: Layout.cardDepthFadeInDuration)
                                .delay(Layout.cardDepthFadeInStagger)
                            : .easeInOut(duration: Layout.cardDepthFadeOutDuration),
                        value: isFlipped
                    )
                    .allowsHitTesting(isFlipped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Layout.frontCardCornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                toggleCardFace()
            }

            if showsQuizButton {
                VStack {
                    Spacer()
                    Button {
                        handleQuizTap()
                    } label: {
                        Text("Quiz Me →")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: Layout.quizButtonHeight)
                            .memoQuizCTAGlassChrome(cornerRadius: Layout.quizButtonCornerRadius)
                            .overlay {
                                RoundedRectangle(cornerRadius: Layout.quizButtonCornerRadius, style: .continuous)
                                    .strokeBorder(theme.quizButtonBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .opacity(isFlipped ? 1 : 0)
                .allowsHitTesting(isFlipped)
            }


        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showBackButton && !isToday)
        .toolbar(isToday ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isLibraryDetail {
                libraryDetailHeader
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsLibraryProgressIndicator,
               let items = libraryProgressItems,
               let idx = libraryProgressIndex,
               let onSelect = onLibraryProgressSelect {
                DrugProgressIndicator(
                    items: items,
                    currentIndex: idx,
                    onSelect: onSelect
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .background(Color.appBackground)
            }
        }
        .toolbar(shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
        .onChange(of: isFlipped) { _, flipped in
            if !flipped {
                hideTabBarWhileScrollingDetail = false
            }
            if isToday {
                LiquidTabBarSuppression.shared.setTodayDrugDetailPresented(flipped)
            }
        }
        .fullScreenCover(isPresented: $showQuiz, onDismiss: {
            isFlipped = false
        }) {
            QuizView(drug: drug, source: isToday ? .daily : .library)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            if isLibraryDetail {
                LiquidTabBarSuppression.shared.libraryStackDidPush()
            }
            if isToday {
                LiquidTabBarSuppression.shared.setTodayDrugDetailPresented(isFlipped)
            }
        }
        .onDisappear {
            if isLibraryDetail {
                LiquidTabBarSuppression.shared.libraryStackDidPop()
            }
            if isToday {
                LiquidTabBarSuppression.shared.setTodayDrugDetailPresented(false)
            }
        }
        .background {
            NavigationControllerAccessor { nav in
                navigationController = nav
            }
            .allowsHitTesting(false)
        }
    }

    private var libraryHorizontalPadding: CGFloat {
        if isToday { return 16 }
        return isLibraryDetail ? 16 : Layout.screenPadding
    }

    private var frontCardContentPadding: CGFloat {
        (isToday || isLibraryDetail) ? Layout.todayFrontCardInternalPadding : Layout.frontCardInternalPadding
    }

    private var libraryDetailHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 40, height: 40)
            }
            .minimumHitTarget()
            .accessibilityLabel("Back")

            if showsLibraryHomeButton {
                Button {
                    if let nav = navigationController {
                        nav.popToRootViewController(animated: true)
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 40, height: 40)
                }
                .minimumHitTarget()
                .accessibilityLabel("Library Home")
            }

            Spacer()

            detailFlagChip
                .frame(minHeight: 40, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color.appBackground)
    }

    /// Same label stack as `TodayView.todayMenuToolbarButton` (`AppScreens.swift`): `MemoToolbarPillMetrics` + square `chipSlotWidth` + `memoToolbarIconChipChrome()`.
    private var detailFlagChip: some View {
        let isFlagged = progress.isDrugFlagged(drug.id)
        return Button {
            progress.toggleDrugFlag(drug.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isFlagged ? "flag.fill" : "flag")
                .font(MemoToolbarPillMetrics.iconFont)
                .foregroundStyle(isFlagged ? .orange : Color(.label))
                .frame(width: MemoToolbarPillMetrics.chipSlotWidth,
                       height: MemoToolbarPillMetrics.chipSlotWidth)
                .memoToolbarIconChipChrome()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFlagged ? "Unflag drug" : "Flag drug")
    }

    private var frontView: some View {
        GeometryReader { proxy in
            let inset = libraryHorizontalPadding
            let cardWidth: CGFloat = {
                // Library drilldown + Growth Archives share Today's full-bleed footprint so the hero
                // card doesn't look narrower than Today; other paths (search list) keep the 0.85 inset.
                if isToday || isLibraryDetail {
                    return max(0, proxy.size.width - inset * 2)
                }
                return proxy.size.width * Layout.frontCardWidthFactor
            }()
            ZStack {
                VStack(spacing: 0) {
                    frontCardFace(cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, inset)
        }
    }

    private func frontCardFace(cardWidth: CGFloat) -> some View {
        let frontShape = RoundedRectangle(cornerRadius: Layout.frontCardCornerRadius, style: .continuous)
        let cardBody = VStack(alignment: .leading, spacing: 0) {
            Text(drug.cardFrontCollectionTag)
                .font(theme.uiLabel)
                .tracking(0.5)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : Color.primary.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.primary.opacity(0.07))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(drug.genericName.capitalized)
                .font(theme.usesSerifHero ? .system(size: 40, weight: .semibold, design: .serif) : .system(size: 40, weight: .bold))
                .foregroundStyle(Color(.label))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Layout.badgeToTitleSpacing)

            Text(drug.brandNames.joined(separator: " / "))
                .font(theme.uiBody)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : Color.primary.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Layout.titleToBrandSpacing)

            Divider()
                .opacity(0.5)
                .padding(.top, Layout.brandToDividerSpacing)

            Text("Tap anywhere to reveal")
                .font(theme.uiSubtle)
                .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.65 : 0.55))
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(hintOpacity)
                .padding(.top, Layout.dividerToHintSpacing)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        hintOpacity = 0.45
                    }
                }
        }
        .padding(frontCardContentPadding)
        .frame(width: cardWidth)

        return cardBody
            .background(theme.cardFrontSurface)
            .clipShape(frontShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 16, x: 0, y: 6)
    }

    private var backView: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.contentSpacing) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(drug.genericName.capitalized)
                                .font(theme.usesSerifHero ? .system(size: 40, weight: .semibold, design: .serif) : .system(size: 40, weight: .bold))
                                .foregroundStyle(detailPrimary)
                                .lineLimit(3)
                                .minimumScaleFactor(0.45)
                                .multilineTextAlignment(.leading)

                            Text(drug.brandNames.joined(separator: " / "))
                                .font(theme.appFont(14))
                                .foregroundStyle(detailPrimary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        detailFlagChip
                    }
                    .padding(.top, isToday ? 0 : 10)
                    .padding(.bottom, 12)

                    whyItMattersCard

                    sectionCard(title: "Mechanism of Action") {
                        Text(drug.mechanismOfAction)
                            .font(theme.appFont(15))
                            .fontWeight(.medium)
                            .foregroundStyle(sectionContentForeground)
                    }

                    bulletSectionCard(
                        title: "Indications",
                        items: drug.indications,
                        iconColor: theme.indicationAccent
                    )
                    dosageSectionCard
                    bulletSectionCard(
                        title: "Side Effects",
                        items: drug.sideEffects
                    )
                    bulletSectionCard(
                        title: "Warnings",
                        items: drug.warnings
                    )
                    bulletSectionCard(title: "Contraindications", items: drug.contraindications)
                    bulletSectionCard(title: "Interactions", items: drug.interactions)
                    bulletSectionCard(title: "Monitoring", items: drug.monitoring)
                    bulletSectionCard(
                        title: "Counseling Points",
                        items: drug.counselingPoints
                    )

                    Text("** For educational purposes only. Not medical advice.")
                        .font(theme.appFont(12))
                        .foregroundStyle(Color(.label))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Space reserved for the Quiz Me button overlay when quiz CTA is shown.
                    Color.clear
                        .frame(height: showsQuizButton ? Layout.quizButtonHeight + 48 : 32)
                }
                .padding(.horizontal, isLibraryDetail || isToday ? 16 : 24)
                .padding(.top, isLibraryDetail ? 12 : (isToday ? 6 : 24))
                .padding(.bottom, isLibraryDetail ? 12 : 24)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y)
            } action: { _, y in
                guard !isToday, isFlipped, !isLibraryDetail else { return }
                let hide = y > 24
                if hideTabBarWhileScrollingDetail != hide {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hideTabBarWhileScrollingDetail = hide
                    }
                }
            }
            .drugListScrollEdgeFade()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
    }

    private var whyItMattersCard: some View {
        VStack(alignment: .leading, spacing: Layout.sectionTitleToContentSpacing) {
            Text("WHY IT MATTERS")
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(theme.whyItMattersAccent)

            Text(drug.pearls.first ?? "")
                .font(theme.appFont(15))
                .italic()
                .fontWeight(.medium)
                .foregroundStyle(sectionContentForeground)
        }
        .padding(.top, Layout.sectionInternalPadding)
        .padding(.bottom, Layout.sectionInternalPadding)
        .padding(.trailing, Layout.sectionInternalPadding)
        .padding(.leading, Layout.sectionInternalPadding + Layout.whyItMattersBarWidth + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                theme.whyItMattersAccent.opacity(0.07)
                Rectangle()
                    .fill(theme.whyItMattersAccent.opacity(0.7))
                    .frame(width: Layout.whyItMattersBarWidth)
                    .padding(.leading, Layout.sectionInternalPadding)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(theme.whyItMattersAccent.opacity(0.20), lineWidth: 1)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Layout.sectionTitleToContentSpacing) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(sectionHeadingMuted)
            content()
        }
        .padding(Layout.sectionInternalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.sectionSurface)
        .clipShape(RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
                .strokeBorder(DrugCardDetailTheme.sectionStroke, lineWidth: 1)
        }
    }

    private func bulletSectionCard(
        title: String,
        items: [String],
        iconName: String = "circle.fill",
        iconColor: Color? = nil
    ) -> some View {
        let resolvedIconColor = iconColor ?? defaultBulletIconColor
        return sectionCard(title: title) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: Layout.bulletRowSpacing) {
                    Image(systemName: iconName)
                        .font(.system(size: Layout.iconSize))
                        .foregroundStyle(resolvedIconColor)
                        .padding(.top, 5)
                    Text(item)
                        .font(theme.appFont(15))
                        .fontWeight(.medium)
                        .foregroundStyle(sectionContentForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var dosageSectionCard: some View {
        sectionCard(title: "Dosage") {
            dosageRow(label: "Adult", value: drug.dosage.adult)
            dosageRow(label: "Renal Adjustment", value: drug.dosage.renalAdjustment)
            dosageRow(label: "Max Dose", value: drug.dosage.maxDose)
        }
    }

    private func dosageRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(theme.appFont(13))
                .fontWeight(.medium)
                .foregroundStyle(sectionContentForeground)
            Text(value)
                .font(theme.appFont(14))
                .fontWeight(.medium)
                .foregroundStyle(sectionContentForeground)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func toggleCardFace() {
        if !isFlipped {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        isFlipped.toggle()
    }

    private func handleQuizTap() {
        let gate: SubscriptionManager.QuizGate = isToday
            ? subscriptions.gateForDailyQuiz()
            : subscriptions.gateForOnDemandQuiz()

        switch gate {
        case .allowed:
            showQuiz = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .requiresSubscription:
            showPaywall = true
        }
    }

}

private struct NavigationControllerAccessor: UIViewControllerRepresentable {
    var onResolve: (UINavigationController?) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            onResolve(uiViewController.navigationController)
        }
    }
}

