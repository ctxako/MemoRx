import Foundation
import SwiftUI

/// Server-driven universal daily drug (`get_current_challenge` + catalog validation).
@MainActor
final class DailyChallengeService: ObservableObject {
    static let shared = DailyChallengeService()

    /// Latest successful assignment from `get_current_challenge` (nil = no row, legacy daily index, or not fetched).
    @Published private(set) var assignment: ServerDailyAssignment?
    /// True when the server assigned a `drug_id` that is still missing after a forced catalog refetch.
    @Published private(set) var challengeDrugMissingFromCatalog = false
    /// Last refresh failed (e.g. RPC missing); app falls back to legacy “rotating index” daily drug.
    @Published private(set) var lastRefreshFailed = false
    /// Human-readable detail when `lastRefreshFailed` is true. Surfaced as a banner in ContentView so
    /// silent failures stop being silent — without it, `assignment` stays nil, the local rotation
    /// shows the wrong drug, and the user has no idea why their daily quiz doesn't award XP.
    @Published private(set) var lastRefreshErrorMessage: String?
    /// Becomes true after the first refreshFromServer() completes (success or failure).
    /// Used by ContentView to hold the splash screen until the authoritative daily drug is known.
    @Published private(set) var hasCompletedInitialFetch = false

    private let defaults = UserDefaults.standard
    private static let completedChallengeDateKey = "serverDailyCompletedChallengeDate"

    private init() {}

    /// `p_user_id` / `auth.uid()` alignment + server assignment present.
    func shouldUseServerDailyCompletion(for drug: Drug) -> Bool {
        guard SupabaseManager.isConfiguredForRemote else { return false }
        guard let aid = assignment?.drugId, !challengeDrugMissingFromCatalog else { return false }
        return aid == drug.id
    }

    func resolvedHighlightDrug(in catalog: [Drug]) -> Drug? {
        guard let id = assignment?.drugId, !challengeDrugMissingFromCatalog else { return nil }
        return catalog.first { $0.id == id }
    }

    func estimatedServerXP(correct: Int, total: Int) -> Int {
        guard let base = assignment?.xpBase, total > 0 else { return 0 }
        return Int((Double(base) * Double(correct) / Double(total)).rounded(.toNearestOrAwayFromZero))
    }

    func hasServerLoggedCompletionForCurrentAssignment() -> Bool {
        guard let date = assignment?.challengeDateRaw else { return false }
        return defaults.string(forKey: Self.completedChallengeDateKey) == date
    }

    func markServerCompletion(forChallengeDate date: String) {
        defaults.set(date, forKey: Self.completedChallengeDateKey)
        objectWillChange.send()
    }

    func refreshFromServer() async {
        defer { hasCompletedInitialFetch = true }
        guard SupabaseManager.isConfiguredForRemote else {
            assignment = nil
            challengeDrugMissingFromCatalog = false
            lastRefreshFailed = false
            lastRefreshErrorMessage = nil
            return
        }

        await SupabaseManager.ensureAnonymousSession()

        let payload: ServerDailyAssignment?
        do {
            payload = try await SupabaseManager.fetchCurrentChallengeAssignment()
            lastRefreshFailed = false
            lastRefreshErrorMessage = nil
        } catch {
            #if DEBUG
            print("[DailyChallenge] refresh failed: \(error)")
            #endif
            SentryReporting.captureSupabaseError(
                error,
                operation: "rpc.fetchCurrentChallengeAssignment",
                userId: nil
            )
            lastRefreshFailed = true
            lastRefreshErrorMessage = "Couldn’t load today’s drug. Daily XP won’t sync until this succeeds. \(error.localizedDescription)"
            assignment = nil
            challengeDrugMissingFromCatalog = false
            return
        }

        applyAssignment(payload)
    }

    /// Called by ContentView when the user taps "Try again" on the daily-challenge banner.
    func retry() async {
        lastRefreshErrorMessage = nil
        await refreshFromServer()
        await ensureCatalogContainsChallengeDrug()
    }

    /// After resolving `assignment`, refetch catalog if the drug is missing.
    func ensureCatalogContainsChallengeDrug() async {
        guard let id = assignment?.drugId else {
            challengeDrugMissingFromCatalog = false
            return
        }
        let catalog = DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
        if catalog.contains(where: { $0.id == id }) {
            challengeDrugMissingFromCatalog = false
            return
        }
        await DrugService.shared.loadFromSupabaseOnLaunch()
        let refreshed = DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
        challengeDrugMissingFromCatalog = !refreshed.contains(where: { $0.id == id })
    }

    private func applyAssignment(_ payload: ServerDailyAssignment?) {
        assignment = payload
        challengeDrugMissingFromCatalog = false
        if let newDate = payload?.challengeDateRaw {
            if let stored = defaults.string(forKey: Self.completedChallengeDateKey), stored != newDate {
                defaults.removeObject(forKey: Self.completedChallengeDateKey)
            }
        }
        if let payload {
            SentryReporting.breadcrumb(
                category: "daily",
                message: "daily.assigned",
                data: [
                    "drug_id": payload.drugId,
                    "challenge_date": payload.challengeDateRaw
                ]
            )
        }
        guard let id = payload?.drugId else { return }
        let catalog = DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
        if !catalog.contains(where: { $0.id == id }) {
            Task { await ensureCatalogContainsChallengeDrug() }
        }
    }
}

struct ServerDailyAssignment: Equatable, Sendable {
    let challengeDateRaw: String
    let drugId: String
    let title: String?
    let difficulty: String?
    let xpBase: Int

    var challengeDateDisplay: String { challengeDateRaw }
}
