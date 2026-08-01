import StoreKit
import SwiftUI

private enum PaywallTheme {
    static let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
    static let goldBorderSelected = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.22)
    static let cardCornerRadius: CGFloat = 14
    static let cardStroke = Color.appSecondaryText.opacity(0.12)
    /// Paywall feature row surface (not `appCardBackground`).
    static let featureCardBackground = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
    static let featureCardBorder = Color.white.opacity(0.07)
}

struct PaywallView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    var subscriptionLapsed: Bool = false
    /// When false, the close (X) button is hidden — used by the mandatory root gate in
    /// `ContentView`, where the view isn't presented modally and `dismiss()` is a no-op
    /// (a visible-but-dead button). Sheet presentations keep the default `true`.
    var isDismissable: Bool = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var hasTimedOutProductLoad = false
    @State private var errorMessage: String?
    @State private var selectedProductID: String = "ctxa.MemoRx.yearly"
    @State private var showPlans = true
    private let monthlyID = "ctxa.MemoRx.monthly"
    private let annualID = "ctxa.MemoRx.yearly"
    private let lifetimeID = "ctxa.MemoRx.lifetime"

    init(subscriptionLapsed: Bool = false, isDismissable: Bool = true) {
        self.subscriptionLapsed = subscriptionLapsed
        self.isDismissable = isDismissable
        self._showPlans = State(initialValue: true)
    }

    private var monthlyProduct: Product? {
        subscriptions.products.first(where: { $0.id == monthlyID })
    }

    private var annualProduct: Product? {
        subscriptions.products.first(where: { $0.id == annualID })
    }

    private var lifetimeProduct: Product? {
        subscriptions.products.first(where: { $0.id == lifetimeID })
    }

    private var isLoadingOptions: Bool {
        !hasTimedOutProductLoad && (subscriptions.isLoadingProducts || monthlyProduct == nil || annualProduct == nil)
    }

    private var shouldShowFallbackPrices: Bool {
        hasTimedOutProductLoad
    }

    private var ctaButtonTitle: String {
        if isPurchasing {
            return "Processing…"
        }

        if selectedProductID == lifetimeID {
            return "Get Lifetime Access"
        }

        if selectedProductID == annualID {
            if subscriptions.isEligibleForIntroOffer {
                return "Start 7-Day Free Trial — Yearly"
            }

            return "Subscribe Yearly"
        }

        if subscriptions.isEligibleForIntroOffer {
            return "Start 7-Day Free Trial — Monthly"
        }

        return "Subscribe Monthly"
    }
    
    private var monthlyPriceDisplay: String {
        monthlyProduct?.displayPrice ?? "$4.99"
    }

    private var annualPriceDisplay: String {
        annualProduct?.displayPrice ?? "$49.99"
    }

    private var legalText: String {
        if selectedProductID == lifetimeID {
            return "Lifetime Access is a one-time purchase and does not renew. Includes daily drug drops, adaptive quizzes, weekly leaderboard, exam pacing, and the full 200+ drug library."
        }
        


        if selectedProductID == annualID {
            if subscriptions.isEligibleForIntroOffer {
                return "Yearly access includes a 7-day free trial, then \(annualPriceDisplay)/year. Renews yearly until canceled. Cancel anytime in your Apple account settings."
            }

            return "Yearly access costs \(annualPriceDisplay)/year. Renews yearly until canceled. Cancel anytime in your Apple account settings."
        }

        if subscriptions.isEligibleForIntroOffer {
            return "Monthly access includes a 7-day free trial, then \(monthlyPriceDisplay)/month. Renews monthly until canceled. Cancel anytime in your Apple account settings."
        }

        return "Monthly access costs \(monthlyPriceDisplay)/month. Renews monthly until canceled. Cancel anytime in your Apple account settings."
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if subscriptionLapsed {
                            lapseBanner
                        }
                        headerBlock

                        paywallFeaturesCard

                        if isLoadingOptions {
                            ProgressView()
                                .padding(.top, 8)
                        } else {
                            productCards

                            startTrialButton
                                .padding(.top, 4)
                        }

                        restoreButton
                            .padding(.top, 6)
                        legalSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(width: 36, height: 36)
                                .background(Color.appCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(PaywallTheme.cardStroke, lineWidth: 1)
                                }
                        }
                        .minimumHitTarget()
                    }
                }
            }
        }
        .task {
            await loadProductsWithTimeout()
            await subscriptions.refreshEntitlements()
        }
        .onAppear { if subscriptions.hasActiveSubscription { dismiss() } }
        .onChange(of: subscriptions.hasActiveSubscription) { _, isActive in
            if isActive { dismiss() }
        }
    }

    private var lapseBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PaywallTheme.warmGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Subscription expired")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PaywallTheme.warmGold)
                Text("Choose a plan below to continue.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PaywallTheme.warmGold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PaywallTheme.warmGold.opacity(0.25), lineWidth: 1)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if subscriptions.isEligibleForIntroOffer {
                Text("7-DAY FREE TRIAL")
                    .font(.system(size: 11, weight: .semibold).smallCaps())
                    .tracking(1.5)
                    .foregroundStyle(PaywallTheme.warmGold)
                    .padding(.bottom, 6)
            }

            heroTitle
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroTitle: some View {
        Text("A new drug every day.\nQuizzes that adapt.\nA leaderboard that resets weekly.")
            .font(.system(size: 32, weight: .semibold, design: .serif))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var paywallFeaturesCard: some View {
        VStack(spacing: 8) {
            paywallFeatureRow("\u{1F4C5}", title: "Daily drug drops", detail: "Fresh content every day, not a static library")
            paywallFeatureRow("\u{1F9E0}", title: "Adaptive quizzes", detail: "Surfaces your weak spots and re-tests them until they stick")
            paywallFeatureRow("\u{1F3C6}", title: "Live weekly leaderboard", detail: "New season every Monday, real competition")
            paywallFeatureRow("\u{23F1}", title: "Exam countdown pacing", detail: "Updates your daily target as your score changes")
            paywallFeatureRow("\u{1F4DA}", title: "Full 200+ drug library", detail: "Every drug, quizzable, with full pharmacology detail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paywallFeatureRow(_ emoji: String, title: String, detail: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(PaywallTheme.warmGold.opacity(0.30))
                .frame(width: 2)
                .padding(.vertical, 6)
                .padding(.leading, 10)

            HStack(alignment: .top, spacing: 10) {
                Text(emoji)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.appFont(14, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text(detail)
                        .font(theme.appFont(12))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
        }
        .background(PaywallTheme.featureCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: PaywallTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaywallTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(PaywallTheme.featureCardBorder, lineWidth: 1)
        }
    }

    private var productCards: some View {
        VStack(spacing: 10) {
            if let annualProduct {
                planSelectableCard(
                    productID: annualID,
                    isSelected: selectedProductID == annualID,
                    badgeLabel: "Best Value",
                    title: "Yearly Access",
                    primaryPrice: "\(annualProduct.displayPrice) / year",
                    detailLines: [
                        subscriptions.isEligibleForIntroOffer
                            ? "7-day free trial, then \(annualProduct.displayPrice)/year"
                            : "Billed yearly at \(annualProduct.displayPrice)/year",
                        "\(perMonthLabel(for: annualProduct)) · Renews yearly until canceled",
                    ]
                )
            } else if shouldShowFallbackPrices {
                planSelectableCard(
                    productID: annualID,
                    isSelected: selectedProductID == annualID,
                    badgeLabel: "Best Value",
                    title: "Yearly Access",
                    primaryPrice: "$49.99 / year",
                    detailLines: [
                        subscriptions.isEligibleForIntroOffer
                            ? "7-day free trial, then $49.99/year"
                            : "Billed yearly at $49.99/year",
                        "$4.17/mo · Renews yearly until canceled",
                    ]
                )
            }

            if let monthlyProduct {
                planSelectableCard(
                    productID: monthlyID,
                    isSelected: selectedProductID == monthlyID,
                    badgeLabel: nil,
                    title: "Monthly Access",
                    primaryPrice: "\(monthlyProduct.displayPrice) / month",
                    detailLines: [
                        subscriptions.isEligibleForIntroOffer
                            ? "7-day free trial, then \(monthlyProduct.displayPrice)/month"
                            : "Billed monthly at \(monthlyProduct.displayPrice)/month",
                        "Renews monthly until canceled",
                    ]
                )
            } else if shouldShowFallbackPrices {
                planSelectableCard(
                    productID: monthlyID,
                    isSelected: selectedProductID == monthlyID,
                    badgeLabel: nil,
                    title: "Monthly Access",
                    primaryPrice: "$4.99 / month",
                    detailLines: [
                        subscriptions.isEligibleForIntroOffer
                            ? "7-day free trial, then $4.99/month"
                            : "Billed monthly at $4.99/month",
                        "Renews monthly until canceled",
                    ]
                )
            }

            if let lifetimeProduct {
                planSelectableCard(
                    productID: lifetimeID,
                    isSelected: selectedProductID == lifetimeID,
                    badgeLabel: "One-Time",
                    title: "Lifetime Access",
                    primaryPrice: lifetimeProduct.displayPrice,
                    detailLines: [
                        "One-time purchase · Does not renew",
                        "Pay once, never pay again",
                    ]
                )
            } else if shouldShowFallbackPrices {
                planSelectableCard(
                    productID: lifetimeID,
                    isSelected: selectedProductID == lifetimeID,
                    badgeLabel: "One-Time",
                    title: "Lifetime Access",
                    primaryPrice: "$99.99",
                    detailLines: [
                        "One-time purchase · Does not renew",
                        "Pay once, never pay again",
                        "Includes daily drug drops, adaptive quizzes, weekly leaderboard, exam pacing, and full 200+ drug library."
                    ]
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(theme.appFont(13))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var startTrialButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            Text(ctaButtonTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(PaywallTheme.warmGold)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || isRestoring)
        .opacity((isPurchasing || isRestoring) ? 0.55 : 1)
    }

    private var restoreButton: some View {
        Button {
            Task {
                await restore()
            }
        } label: {
            Text(isRestoring ? "Restoring…" : "Restore Purchases")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaywallTheme.warmGold)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PaywallTheme.warmGold.opacity(0.28), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .disabled(isRestoring)
        .opacity(isRestoring ? 0.55 : 1)
    }

    private var legalSection: some View {
        VStack(spacing: 10) {
            Text(legalText)
                .font(theme.appFont(11))
                .foregroundStyle(Color.appTertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                NavigationLink {
                    TermsOfUseView()
                } label: {
                    legalLinkLabel("Terms of Use")
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    legalLinkLabel("Privacy Policy")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private func planSelectableCard(
        productID: String,
        isSelected: Bool,
        badgeLabel: String?,
        title: String,
        primaryPrice: String,
        detailLines: [String]
    ) -> some View {
        Button {
            selectedProductID = productID
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    if let badge = badgeLabel {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PaywallTheme.warmGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PaywallTheme.warmGold.opacity(0.12))
                            .overlay {
                                Capsule()
                                    .strokeBorder(PaywallTheme.warmGold.opacity(0.35), lineWidth: 1)
                            }
                            .clipShape(Capsule())
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)

                    Text(primaryPrice)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(isSelected ? PaywallTheme.warmGold : Color.appPrimaryText)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .padding(.trailing, 36)

                planRadio(isSelected: isSelected)
                    .padding(14)
            }
            .background {
                ZStack {
                    Color.appCardBackground
                    if isSelected {
                        PaywallTheme.warmGold.opacity(0.08)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PaywallTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaywallTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? PaywallTheme.goldBorderSelected : PaywallTheme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
    }

    private func planRadio(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? PaywallTheme.warmGold.opacity(0.55) : Color.appSecondaryText.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(PaywallTheme.warmGold)
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func perMonthLabel(for product: Product) -> String {
        let monthly = product.price / Decimal(12)
        let code = Locale.current.currency?.identifier ?? "USD"
        let formatted = monthly.formatted(.currency(code: code).precision(.fractionLength(2)))
        return "\(formatted)/mo"
    }

    private func purchaseSelected() async {
        errorMessage = nil

        if let product = subscriptions.products.first(where: { $0.id == selectedProductID }) {
            await purchase(product)
            return
        }

        await subscriptions.refreshProducts()

        if let product = subscriptions.products.first(where: { $0.id == selectedProductID }) {
            await purchase(product)
        } else {
            errorMessage = "Unable to connect to App Store. Please try again."
        }
    }

    private func purchase(_ product: Product) async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let outcome = try await subscriptions.purchase(product)

            switch outcome {
            case .purchased:
                dismiss()

            case .pending:
                errorMessage = "Purchase is pending — you'll be unlocked automatically once confirmed by Apple."

            case .cancelled:
                break
            }
        } catch {
            let nsError = error as NSError
            print("Purchase failed:", nsError.domain, nsError.code, nsError.localizedDescription)

            errorMessage = "Unable to complete purchase. Please check your App Store account and try again."
        }
    }

    private func restore() async {
        errorMessage = nil
        isRestoring = true
        await subscriptions.restorePurchases()
        isRestoring = false
        if subscriptions.hasActiveSubscription {
            dismiss()
        } else {
            errorMessage = "No active subscription found."
        }
    }

    private func loadProductsWithTimeout() async {
        hasTimedOutProductLoad = false

        if subscriptions.hasAllSubscriptionProductsLoaded() {
            return
        }

        if subscriptions.isLoadingProducts {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if subscriptions.hasAllSubscriptionProductsLoaded() { return }
                if !subscriptions.isLoadingProducts { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if subscriptions.hasAllSubscriptionProductsLoaded() {
                return
            }
        }

        await subscriptions.refreshProducts()

        let pollDeadline = Date().addingTimeInterval(5)
        while Date() < pollDeadline {
            if subscriptions.hasAllSubscriptionProductsLoaded() || !subscriptions.isLoadingProducts {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if !subscriptions.hasAllSubscriptionProductsLoaded() {
            hasTimedOutProductLoad = true
        }
    }

    private func legalLinkLabel(_ title: String) -> some View {
        Text(title)
            .font(theme.appFont(12, weight: .medium))
            .foregroundStyle(PaywallTheme.warmGold.opacity(0.45))
            .underline()
    }
}
