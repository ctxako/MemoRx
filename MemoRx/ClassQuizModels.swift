import Foundation

struct ClassQuizGuide: Codable, Identifiable {
    let subCollection: SubCollection
    let displayName: String
    let suffixes: [String]
    let classUses: [String]
    let hallmarkSideEffects: [String]
    let highYieldPearls: [String]
    let highRiskMeds: [String]

    var id: String { subCollection.rawValue }

    enum CodingKeys: String, CodingKey {
        case subCollection = "sub_collection"
        case displayName = "display_name"
        case suffixes
        case classUses = "class_uses"
        case hallmarkSideEffects = "hallmark_side_effects"
        case highYieldPearls = "high_yield_pearls"
        case highRiskMeds = "high_risk_meds"
    }
}

struct ClassQuizHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let selectedSubCollections: [String]
    let selectedClassNames: [String]
    let questionCount: Int
    let correctCount: Int
    let totalCount: Int
    let scorePercent: Int
}

@MainActor
final class ClassQuizGuideService {
    static let shared = ClassQuizGuideService()

    private(set) var guides: [ClassQuizGuide] = []
    private(set) var loadErrorMessage: String?
    private let cacheKey = "cachedClassQuizGuidesPayload"

    private init() {}

    func loadFromSupabaseOnLaunch() async {
        do {
            let remote = try await SupabaseManager.fetchRemoteClassQuizGuides()
            if !remote.isEmpty {
                guides = remote
                loadErrorMessage = nil
                cacheGuides(remote)
                return
            }
            if AppRuntimeConfig.cloudContentOnly {
                if applyCachedGuides(clearErrorMessage: true) {
                    loadErrorMessage = "Cloud returned no class quiz guides. Showing last saved content."
                    return
                }
                if applyBundledGuides() {
                    loadErrorMessage = "Cloud returned no class quiz guides. Using bundled content."
                    return
                }
                guides = []
                loadErrorMessage = "Cloud content is enabled, but no class quiz guides were returned from Supabase."
                return
            }
        } catch {
            #if DEBUG
            print("ClassQuizGuideService remote fetch failed: \(error)")
            #endif
            SentryReporting.captureSupabaseError(
                error,
                operation: "class_quiz_guides.fetchRemote",
                userId: nil
            )
            if AppRuntimeConfig.cloudContentOnly {
                if applyCachedGuides(clearErrorMessage: true) {
                    loadErrorMessage = "Couldn’t refresh class quiz content from cloud. Showing last saved content."
                    return
                }
                if applyBundledGuides() {
                    loadErrorMessage = "Couldn’t refresh class quiz content from cloud. Using bundled content."
                    return
                }
                guides = []
                loadErrorMessage = "Unable to load class quiz cloud content right now."
                return
            }
        }

        if applyCachedGuides(clearErrorMessage: true) {
            return
        }

        loadLocalBundleFallback()
    }

    func load() {
        if AppRuntimeConfig.cloudContentOnly {
            if applyCachedGuides(clearErrorMessage: true) {
                loadErrorMessage = nil
                return
            }
            if applyBundledGuides() {
                loadErrorMessage = nil
                return
            }
            guides = []
            loadErrorMessage = "No saved or bundled class quiz content is available offline."
            return
        }
        loadLocalBundleFallback()
    }

    @discardableResult
    private func applyCachedGuides(clearErrorMessage: Bool) -> Bool {
        guard let cached = readCachedGuides(), !cached.isEmpty else { return false }
        guides = cached
        if clearErrorMessage { loadErrorMessage = nil }
        return true
    }

    @discardableResult
    private func applyBundledGuides() -> Bool {
        do {
            guides = try Bundle.main.decodeOrThrow([ClassQuizGuide].self, from: "class_quizzes.json")
            loadErrorMessage = nil
            cacheGuides(guides)
            return true
        } catch {
            return false
        }
    }

    private func loadLocalBundleFallback() {
        do {
            guides = try Bundle.main.decodeOrThrow([ClassQuizGuide].self, from: "class_quizzes.json")
            loadErrorMessage = nil
            cacheGuides(guides)
        } catch {
            guides = []
            loadErrorMessage = "Class quiz content is unavailable right now."
            #if DEBUG
            print("ClassQuizGuideService.load error in class_quizzes.json: \(error)")
            #endif
        }
    }

    private func cacheGuides(_ value: [ClassQuizGuide]) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey)
    }

    private func readCachedGuides() -> [ClassQuizGuide]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([ClassQuizGuide].self, from: data)
    }
}
