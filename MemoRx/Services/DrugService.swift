import Foundation

@MainActor
final class DrugService: ObservableObject {
    static let shared = DrugService()
    static var orderedDrugs: [Drug] = []

    @Published private(set) var drugs: [Drug] = []
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var isLoading = false
    private let cacheKey = "cachedDrugsPayload"

    private init() {}

    func loadFromSupabaseOnLaunch() async {
        // Populate drugs from cache immediately so the splash clears after its animation
        // rather than waiting for the network. The remote fetch below will overwrite with
        // fresh data once it arrives.
        if drugs.isEmpty {
            _ = applyCachedDrugs(clearErrorMessage: true) || applyBundledDrugs()
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remote = try await SupabaseManager.fetchRemoteDrugs()
            if !remote.isEmpty {
                drugs = remote
                loadErrorMessage = nil
                cacheDrugs(remote)
                DrugService.orderedDrugs = DrugService.buildOrderedDrugs()
                cleanupStaleKeys()
                return
            }
            if AppRuntimeConfig.cloudContentOnly {
                if applyCachedDrugs(clearErrorMessage: true) {
                    loadErrorMessage = "Cloud returned no drugs. Showing your last saved library."
                    return
                }
                if applyBundledDrugs() {
                    loadErrorMessage = "Cloud returned no drugs. Using the bundled library."
                    return
                }
                drugs = []
                DrugService.orderedDrugs = []
                loadErrorMessage = "Cloud content is enabled, but no drugs were returned from Supabase."
                return
            }
        } catch {
            #if DEBUG
            print("DrugService remote fetch failed: \(error)")
            #endif
            SentryReporting.captureSupabaseError(
                error,
                operation: "drugs.fetchRemote",
                userId: nil
            )
            if AppRuntimeConfig.cloudContentOnly {
                if applyCachedDrugs(clearErrorMessage: true) {
                    loadErrorMessage = "Couldn’t refresh from cloud. Showing your last saved library."
                    return
                }
                if applyBundledDrugs() {
                    loadErrorMessage = "Couldn’t refresh from cloud. Using the bundled library."
                    return
                }
                drugs = []
                DrugService.orderedDrugs = []
                loadErrorMessage = "Unable to load cloud drug content right now. Check your network and Supabase tables."
                return
            }
        }

        if applyCachedDrugs(clearErrorMessage: true) {
            return
        }

        loadLocalBundleFallback()
    }

    func load() {
        if AppRuntimeConfig.cloudContentOnly {
            if applyCachedDrugs(clearErrorMessage: true) {
                loadErrorMessage = nil
                return
            }
            if applyBundledDrugs() {
                loadErrorMessage = nil
                return
            }
            drugs = []
            DrugService.orderedDrugs = []
            loadErrorMessage = "No saved or bundled drug library is available offline."
            return
        }
        loadLocalBundleFallback()
    }

    @discardableResult
    private func applyCachedDrugs(clearErrorMessage: Bool) -> Bool {
        guard let cached = readCachedDrugs(), !cached.isEmpty else { return false }
        drugs = cached
        if clearErrorMessage { loadErrorMessage = nil }
        DrugService.orderedDrugs = DrugService.buildOrderedDrugs()
        cleanupStaleKeys()
        return true
    }

    @discardableResult
    private func applyBundledDrugs() -> Bool {
        do {
            drugs = try Bundle.main.decodeOrThrow([Drug].self, from: "drugs.json")
            loadErrorMessage = nil
            cacheDrugs(drugs)
            DrugService.orderedDrugs = DrugService.buildOrderedDrugs()
            cleanupStaleKeys()
            return true
        } catch {
            return false
        }
    }

    private func loadLocalBundleFallback() {
        do {
            drugs = try Bundle.main.decodeOrThrow([Drug].self, from: "drugs.json")
            loadErrorMessage = nil
            cacheDrugs(drugs)
        } catch {
            drugs = []
            loadErrorMessage = "We couldn't load the drug library right now. Please restart the app."
            #if DEBUG
            print("DrugService.load error in drugs.json: \(error)")
            #endif
        }
        DrugService.orderedDrugs = DrugService.buildOrderedDrugs()
        cleanupStaleKeys()
    }

    private func cacheDrugs(_ value: [Drug]) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey)
    }

    private func readCachedDrugs() -> [Drug]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([Drug].self, from: data)
    }

    // MARK: - Helpers

    private static func buildOrderedDrugs() -> [Drug] {
        let grouped = Dictionary(grouping: DrugService.shared.drugs, by: { $0.subCollection })
        let collectionOrder = KnownSubCollection.preferredOrder
        var result: [Drug] = []
        for sub in collectionOrder {
            if let drugs = grouped[sub] {
                result += drugs.sorted {
                    $0.genericName.localizedCaseInsensitiveCompare($1.genericName) == .orderedAscending
                }
            }
        }
        let handled = Set(collectionOrder)
        let remainingSubs = grouped.keys
            .filter { !handled.contains($0) }
            .sorted { subCollectionDisplayName($0).localizedCaseInsensitiveCompare(subCollectionDisplayName($1)) == .orderedAscending }
        for sub in remainingSubs {
            guard let drugs = grouped[sub] else { continue }
            result += drugs.sorted {
                $0.genericName.localizedCaseInsensitiveCompare($1.genericName) == .orderedAscending
            }
        }
        return result
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }

    private func cleanupStaleKeys() {
        let today = DrugService.todayString()
        let defaults = UserDefaults.standard
        let staleKeys = defaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix("dailyDrugIndex_") ||
            (key.hasPrefix("quizXPAwarded_") && !key.hasSuffix("_\(today)")) ||
            (key.hasPrefix("dailyQuizXPAwarded_") && key != "dailyQuizXPAwarded_\(today)")
        }
        staleKeys.forEach { defaults.removeObject(forKey: $0) }
    }
}
