import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum QuizGate {
        case allowed
        case requiresSubscription
    }

    enum PurchaseOutcome {
        case purchased
        case pending
        case cancelled
    }

    private enum ProductIDs {
        static let monthly = "ctxa.MemoRx.monthly"
        static let annual = "ctxa.MemoRx.yearly"
        static let lifetime = "ctxa.MemoRx.lifetime"
        static let all = [monthly, annual, lifetime]
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var subscriptionStatusLabel: String = ""
    @Published private(set) var isInTrial = false
    @Published private(set) var trialDaysRemaining: Int = 0
    @Published private(set) var trialEndDate: Date? = nil
    @Published private(set) var isEligibleForIntroOffer: Bool = true

    private var updatesTask: Task<Void, Never>?
    /// Coalesces overlapping `refreshProducts()` calls onto a single StoreKit fetch.
    private var inFlightProductsRefresh: Task<Void, Never>?
    private var isLifetime: Bool {
        UserDefaults.standard.bool(forKey: "isLifetime")
    }

    private init() {
        // configureOnLaunch() — called once from MemoRxApp.init() — handles
        // the initial refreshProducts() + refreshEntitlements() and sets up the
        // Transaction.updates listener.  Nothing needed here.
    }

    deinit {
        updatesTask?.cancel()
    }

    func configureOnLaunch() async {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
                await self.refreshIntroOfferEligibility()
            }
        }

        await refreshProducts()
        await refreshEntitlements()
        await refreshIntroOfferEligibility()
    }

    /// Both subscription SKUs present — usually after `configureOnLaunch()` / `refreshProducts()`.
    func hasAllSubscriptionProductsLoaded() -> Bool {
        ProductIDs.all.allSatisfy { id in products.contains(where: { $0.id == id }) }
    }

    func refreshProducts() async {
        if let existing = inFlightProductsRefresh {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            await self.performProductsFetch()
        }
        inFlightProductsRefresh = task
        await task.value
        inFlightProductsRefresh = nil
    }

    private func performProductsFetch() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        #if DEBUG
        print("[SubscriptionManager] refreshProducts start. Requesting product IDs: \(ProductIDs.all)")
        #endif
        do {
            let fetched = try await Product.products(for: ProductIDs.all)
            #if DEBUG
            let fetchedIDs = fetched.map(\.id)
            print("[SubscriptionManager] Product.products(for:) succeeded. Returned \(fetched.count) products. IDs: \(fetchedIDs)")
            #endif
            products = fetched.sorted {
                let lhs = ProductIDs.all.firstIndex(of: $0.id) ?? .max
                let rhs = ProductIDs.all.firstIndex(of: $1.id) ?? .max
                return lhs < rhs
            }
            #if DEBUG
            let sortedIDs = products.map(\.id)
            print("[SubscriptionManager] refreshProducts sorted result count: \(products.count). Sorted IDs: \(sortedIDs)")
            #endif
        } catch {
            #if DEBUG
            print("[SubscriptionManager] Product.products(for:) failed for IDs \(ProductIDs.all). Error: \(error)")
            let nsError = error as NSError
            print("[SubscriptionManager] StoreKit error details domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
            #endif
            products = []
        }
    }

    /// Apply a server-confirmed lifetime grant. Pass `nil` when the server is
    /// unreachable so an offline comp user keeps their entitlement.
    func applyServerLifetimeGrant(_ isLifetime: Bool?) async {
        guard let isLifetime else { return }
        UserDefaults.standard.set(isLifetime, forKey: "isLifetime")
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        if isLifetime {
            hasActiveSubscription = true
            subscriptionStatusLabel = "Lifetime"
            isInTrial = false
            trialDaysRemaining = 0
            trialEndDate = nil
            return
        }
        var active = false
        var label = ""
        var inTrial = false
        var daysLeft = 0
        var endDate: Date? = nil
        var latestJWS: String? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductIDs.all.contains(transaction.productID) else { continue }
            // Revocation check: belt-and-suspenders — currentEntitlements already excludes
            // revoked transactions, but we verify explicitly.
            guard transaction.revocationDate == nil else { continue }
            // NOTE: No expirationDate < Date() check here. Transaction.currentEntitlements
            // already excludes expired and billing-retry transactions; keeping that check
            // would incorrectly lock out grace-period users whose expirationDate is past
            // but whose subscription still grants access.
            if transaction.productID == ProductIDs.lifetime {
                UserDefaults.standard.set(true, forKey: "isLifetime")
                label = "Lifetime"
            } else {
                label = transaction.productID == ProductIDs.monthly ? "Monthly" : "Annual"
                if let offerType = transaction.offerType,
                   offerType == .introductory,
                   let expiration = transaction.expirationDate {
                    inTrial = true
                    endDate = expiration
                    let seconds = expiration.timeIntervalSince(Date())
                    daysLeft = seconds > 0 ? max(1, Int(ceil(seconds / 86400))) : 0
                }
            }
            latestJWS = result.jwsRepresentation
            active = true
            break
        }
        hasActiveSubscription = active
        subscriptionStatusLabel = active ? label : ""
        isInTrial = inTrial
        trialDaysRemaining = daysLeft
        trialEndDate = endDate

        // Sync entitlement state to server (fire-and-forget).
        if active, let jws = latestJWS {
            syncSubscriptionToServer(jwsTransaction: jws)
        } else if !active {
            clearSubscriptionOnServer()
        }
    }

    func refreshIntroOfferEligibility() async {
        let subProducts = products.filter { $0.type == .autoRenewable }
        guard let first = subProducts.first else {
            isEligibleForIntroOffer = true
            return
        }
        isEligibleForIntroOffer = await (first.subscription?.isEligibleForIntroOffer ?? true)
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        do {
            let userId = await SupabaseManager.currentUserId()
            let result: Product.PurchaseResult
            if let userId {
                result = try await product.purchase(options: [.appAccountToken(userId)])
            } else {
                result = try await product.purchase()
            }

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    #if DEBUG
                    print("[SubscriptionManager] Purchase failed: unverified transaction")
                    #endif
                    return .cancelled
                }

                await transaction.finish()

                // Sync to Supabase only after StoreKit succeeds.
                syncSubscriptionToServer(jwsTransaction: verification.jwsRepresentation)

                // Refresh local StoreKit entitlement state.
                await refreshEntitlements()

                // Trust the verified transaction immediately.
                // currentEntitlements can lag right after purchase.
                if !hasActiveSubscription {
                    if transaction.productID == ProductIDs.lifetime {
                        UserDefaults.standard.set(true, forKey: "isLifetime")
                        subscriptionStatusLabel = "Lifetime"
                    } else if transaction.productID == ProductIDs.monthly {
                        subscriptionStatusLabel = "Monthly"
                    } else if transaction.productID == ProductIDs.annual {
                        subscriptionStatusLabel = "Yearly"
                    }

                    hasActiveSubscription = true
                }

                await refreshIntroOfferEligibility()
                return .purchased

            case .userCancelled:
                return .cancelled

            case .pending:
                return .pending

            @unknown default:
                return .cancelled
            }
        } catch {
            #if DEBUG
            let nsError = error as NSError
            print("[SubscriptionManager] product.purchase() failed")
            print("[SubscriptionManager] domain:", nsError.domain)
            print("[SubscriptionManager] code:", nsError.code)
            print("[SubscriptionManager] description:", nsError.localizedDescription)
            print("[SubscriptionManager] userInfo:", nsError.userInfo)
            #endif

            throw error
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            // No-op; entitlement refresh still runs.
        }
        await refreshEntitlements()
        await refreshIntroOfferEligibility()
    }

    func canUseCustomQuizzes() -> Bool {
        hasActiveSubscription
    }

    func canUseOnDemandDrugSelection() -> Bool {
        hasActiveSubscription
    }

    func canUseAppCustomization() -> Bool {
        hasActiveSubscription
    }

    func gateForDailyQuiz() -> QuizGate {
        hasActiveSubscription ? .allowed : .requiresSubscription
    }

    func gateForOnDemandQuiz() -> QuizGate {
        hasActiveSubscription ? .allowed : .requiresSubscription
    }


    // MARK: - Reset

    /// Synchronously resets all subscription state to defaults.
    /// Call after sign-out or account deletion so the next session
    /// starts clean without waiting for configureOnLaunch().
    @MainActor
    func reset() {
        hasActiveSubscription = false
        subscriptionStatusLabel = ""
        isInTrial = false
        trialDaysRemaining = 0
        trialEndDate = nil
        isEligibleForIntroOffer = true
    }


    // MARK: - Server Subscription Sync

    /// Sync the StoreKit transaction to the server so the edge function can validate
    /// the signed JWS independently. Fire-and-forget: local StoreKit state is the
    /// source of truth for the UI; server sync is best-effort.
    private func syncSubscriptionToServer(jwsTransaction: String) {
        Task.detached(priority: .utility) {
            guard SupabaseManager.isConfiguredForRemote else { return }
            guard let userId = await SupabaseManager.currentUserId() else {
                #if DEBUG
                print("[SubscriptionManager] syncSubscriptionToServer: no user id, skipping")
                #endif
                return
            }
            do {
                let session = try await SupabaseManager.client.auth.session
                let jwt = session.accessToken

                let url = URL(string: "https://edkyksduuzszahqidntq.supabase.co/functions/v1/sync-subscription")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

                let body: [String: String] = [
                    "user_id": userId.uuidString.lowercased(),
                    "signed_transaction_info": jwsTransaction
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[SubscriptionManager] syncSubscriptionToServer completed, status: \(status)")
                #endif
            } catch {
                #if DEBUG
                print("[SubscriptionManager] syncSubscriptionToServer failed: \(error)")
                #endif
            }
        }
    }

    /// Notify the server that the user has no active entitlements so it can clear
    /// any stale subscription state.
    private func clearSubscriptionOnServer() {
        Task.detached(priority: .utility) {
            guard SupabaseManager.isConfiguredForRemote else { return }
            guard let userId = await SupabaseManager.currentUserId() else { return }
            do {
                let session = try await SupabaseManager.client.auth.session
                let jwt = session.accessToken

                let url = URL(string: "https://edkyksduuzszahqidntq.supabase.co/functions/v1/sync-subscription")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

                let body: [String: Any] = [
                    "user_id": userId.uuidString.lowercased(),
                    "clear": true
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[SubscriptionManager] clearSubscriptionOnServer completed, status: \(status)")
                #endif
            } catch {
                #if DEBUG
                print("[SubscriptionManager] clearSubscriptionOnServer failed: \(error)")
                #endif
            }
        }
    }

}
