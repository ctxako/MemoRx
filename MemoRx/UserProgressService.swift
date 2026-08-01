import Combine
import Foundation

struct LastDrugQuizSessionSummary: Codable, Equatable, Sendable {
    let drugId: String
    let correctCount: Int
    let totalCount: Int
    let timestamp: TimeInterval

    var scorePercent: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(correctCount) / Double(totalCount)) * 100)
    }
}

struct DrugSRSState: Codable {
    var repetitionNumber: Int
    var easeFactor: Double
    var intervalDays: Int
}

struct QuizSessionFinalizeResult: Sendable {
    var userVisibleError: String?
    /// Server-side daily XP just granted (0 when not a server-daily quiz or already completed).
    var dailyXpAwarded: Int = 0
    /// Server-side streak-milestone bonus granted alongside the daily XP, if any.
    var milestoneBonus: Int = 0
    /// The biggest streak-milestone unlocked by this completion (e.g. 7, 14, 30, 90), or nil.
    var milestoneDay: Int?
}

@MainActor
final class UserProgressService: ObservableObject {
    static let shared = UserProgressService()

    private enum Keys {
        static let totalXP = "totalXP"
        static let weeklyXP = "weeklyXP"
        static let streak = "streak"
        static let lastStudyDate = "lastStudyDate"
        static let drugScores = "drugScores"
        static let drugScoreSources = "drugScoreSources"
        static let drugDifficultyRatings = "drugDifficultyRatings"
        static let flaggedDrugIds = "flaggedDrugIds"
        static let drugNextReview = "drugNextReview"
        static let pendingSyncNeeded = "pendingSyncNeeded"
        /// JSON `[PendingSyncEvent]` — drugs that still need a successful Supabase sync after retries.
        static let pendingSyncQueueEvents = "pendingSyncQueueEventsV1"
        static let dailyDrugSequenceAnchorDate = "dailyDrugSequenceAnchorDate"
        static let classQuizHistory = "classQuizHistory"
        static let lastDrugQuizSession = "lastDrugQuizSessionV1"
        static let lastDailyQuizSession = "lastDailyQuizSessionV1"
        /// Persists first-seen `created_at` for stable `public.users` upserts (`SupabaseManager.UserRow`).
        static let profileCreatedAtForSupabase = "supabaseProfileCreatedAt"
        static let drugSRSStates = "drugSRSStatesV1"
        /// Set when `setOnboardingCompleted` couldn't reach the server; retried on next launch.
        static let onboardingCompletedNeedsSync = "onboardingCompletedNeedsSyncV1"
    }

    enum QuizSource: String {
        case unknown
        case library
        case daily
    }

    enum QuizScoreFilter {
        case all
        case library
        case daily
    }

    @Published var totalXP: Int
    @Published var weeklyXP: Int
    @Published var streak: Int
    @Published var lastStudyDateString: String

    @Published var drugScores: [String: [Int]]
    /// Per-attempt source labels aligned to `drugScores` indices (same order, append-only).
    @Published var drugScoreSources: [String: [String]]
    /// User-reported mastery tier per drug (1…4). Persisted locally.
    @Published var drugDifficultyRatings: [String: Int]
    /// User-selected study flags, independent of score/mastery/difficulty.
    @Published var flaggedDrugIds: Set<String>
    @Published var drugNextReview: [String: Date]
    @Published var drugSRSStates: [String: DrugSRSState]
    @Published var classQuizHistory: [ClassQuizHistoryEntry]
    @Published var lastDrugQuizSession: LastDrugQuizSessionSummary?
    @Published var lastDailyQuizSession: LastDrugQuizSessionSummary?

    private let defaults = UserDefaults.standard

    private struct PendingSyncEvent: Codable, Equatable {
        var drugId: String
        var enqueuedAt: TimeInterval
    }

    init() {
        self.totalXP = defaults.integer(forKey: Keys.totalXP)
        self.weeklyXP = defaults.integer(forKey: Keys.weeklyXP)
        self.streak = defaults.integer(forKey: Keys.streak)
        self.lastStudyDateString = defaults.string(forKey: Keys.lastStudyDate) ?? ""
        self.drugScores = (defaults.dictionary(forKey: Keys.drugScores) as? [String: [Int]]) ?? [:]
        self.drugScoreSources = (defaults.dictionary(forKey: Keys.drugScoreSources) as? [String: [String]]) ?? [:]
        if let raw = defaults.dictionary(forKey: Keys.drugDifficultyRatings) {
            self.drugDifficultyRatings = raw.compactMapValues { $0 as? Int }
        } else {
            self.drugDifficultyRatings = [:]
        }
        self.flaggedDrugIds = Set(defaults.stringArray(forKey: Keys.flaggedDrugIds) ?? [])
        self.drugNextReview = [:]

        if let raw = defaults.dictionary(forKey: Keys.drugNextReview) as? [String: Double] {
            self.drugNextReview = raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        if let data = defaults.data(forKey: Keys.drugSRSStates),
           let decoded = try? JSONDecoder().decode([String: DrugSRSState].self, from: data) {
            self.drugSRSStates = decoded
        } else {
            self.drugSRSStates = [:]
        }
        if let data = defaults.data(forKey: Keys.classQuizHistory),
           let decoded = try? JSONDecoder().decode([ClassQuizHistoryEntry].self, from: data) {
            self.classQuizHistory = decoded
        } else {
            self.classQuizHistory = []
        }

        if let sessionData = defaults.data(forKey: Keys.lastDrugQuizSession),
           let decodedSession = try? JSONDecoder().decode(LastDrugQuizSessionSummary.self, from: sessionData) {
            self.lastDrugQuizSession = decodedSession
        } else {
            self.lastDrugQuizSession = nil
        }

        if let dailySessionData = defaults.data(forKey: Keys.lastDailyQuizSession),
           let decodedDailySession = try? JSONDecoder().decode(LastDrugQuizSessionSummary.self, from: dailySessionData) {
            self.lastDailyQuizSession = decodedDailySession
        } else {
            self.lastDailyQuizSession = nil
        }

        repairLastDailyQuizSessionIfNeeded()

        // Weekly XP is refreshed authoritatively on cold launch / foreground / Growth appear
        // via `refreshAuthoritativeProgressFromServer()`. The previous init-time fetch was
        // redundant and racy with that path.
        migrateLegacyPendingSyncIfNeeded()
        if !loadPendingSyncEvents().isEmpty {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await SupabaseManager.ensureAnonymousSession()
                guard let uid = await SupabaseManager.currentUserId() else { return }
                await flushPendingSyncQueue(userId: uid, maxDrugs: 10)
            }
        }

        // Retry a completion-flag write that failed on a previous launch (offline finish, etc.)
        // so the server's `has_completed_onboarding` eventually matches the local flag.
        if defaults.bool(forKey: Keys.onboardingCompletedNeedsSync) {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await pushOnboardingCompletedWithRetry()
            }
        }
    }

    func save() {
        defaults.set(totalXP, forKey: Keys.totalXP)
        defaults.set(weeklyXP, forKey: Keys.weeklyXP)
        defaults.set(streak, forKey: Keys.streak)
        defaults.set(lastStudyDateString, forKey: Keys.lastStudyDate)
        defaults.set(drugScores, forKey: Keys.drugScores)
        defaults.set(drugScoreSources, forKey: Keys.drugScoreSources)
        defaults.set(drugDifficultyRatings, forKey: Keys.drugDifficultyRatings)
        defaults.set(Array(flaggedDrugIds), forKey: Keys.flaggedDrugIds)
        let rawDates = drugNextReview.mapValues { $0.timeIntervalSince1970 }
        defaults.set(rawDates, forKey: Keys.drugNextReview)
        if let srsData = try? JSONEncoder().encode(drugSRSStates) {
            defaults.set(srsData, forKey: Keys.drugSRSStates)
        }
        if let historyData = try? JSONEncoder().encode(classQuizHistory) {
            defaults.set(historyData, forKey: Keys.classQuizHistory)
        }
        if let session = lastDrugQuizSession,
           let sessionData = try? JSONEncoder().encode(session) {
            defaults.set(sessionData, forKey: Keys.lastDrugQuizSession)
        } else {
            defaults.removeObject(forKey: Keys.lastDrugQuizSession)
        }
        if let dailySession = lastDailyQuizSession,
           let dailySessionData = try? JSONEncoder().encode(dailySession) {
            defaults.set(dailySessionData, forKey: Keys.lastDailyQuizSession)
        } else {
            defaults.removeObject(forKey: Keys.lastDailyQuizSession)
        }
    }

    func calculateQuizXP(correct: Int, total: Int) -> Int {
        guard total > 0 else { return 1 }
        let pct = Double(correct) / Double(total)
        switch pct {
        case 0.9...1.0: return 25
        case 0.7..<0.9: return 18
        case 0.3..<0.7: return 12
        case 0.01..<0.3: return 5
        default: return 1
        }
    }

    private func dailyQuizXPKey(for dateKey: String? = nil) -> String {
        "dailyQuizXPAwarded_\(dateKey ?? todayString())"
    }

    private func normalizedIndex(_ rawIndex: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((rawIndex % count) + count) % count
    }

    func hasAwardedDailyQuizXPToday() -> Bool {
        if DailyChallengeService.shared.hasServerLoggedCompletionForCurrentAssignment() {
            return true
        }
        return defaults.bool(forKey: dailyQuizXPKey())
    }

    /// True when this drug is “today’s” highlight for XP/streak: server assignment (when active) or legacy rotating index.
    func isEffectiveTodaysDrug(_ drug: Drug, allDrugs: [Drug]? = nil) -> Bool {
        if DailyChallengeService.shared.shouldUseServerDailyCompletion(for: drug) {
            return true
        }
        return isTodaysDrug(drug, allDrugs: allDrugs)
    }

    func isTodaysDrug(_ drug: Drug, allDrugs: [Drug]? = nil) -> Bool {
        if let serverId = DailyChallengeService.shared.assignment?.drugId,
           !DailyChallengeService.shared.challengeDrugMissingFromCatalog,
           serverId == drug.id {
            return true
        }
        let source = allDrugs ?? (DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs)
        guard !source.isEmpty else { return false }
        let idx = normalizedIndex(todaysDrugIndex(), count: source.count)
        return source[idx].id == drug.id
    }

    /// Finishes a quiz session: appends scores, awards XP (legacy or server RPC), streak, Supabase sync, and quiz_attempts log.
    func finalizeQuizSession(
        drug: Drug,
        correctCount: Int,
        totalCount: Int,
        allDrugs: [Drug],
        source: QuizSource
    ) async -> QuizSessionFinalizeResult {
        let safeTotal = max(totalCount, 1)
        let pct = Int((Double(correctCount) / Double(safeTotal)) * 100)

        let todayQuiz = isEffectiveTodaysDrug(drug, allDrugs: allDrugs)
        let serverDaily = DailyChallengeService.shared.shouldUseServerDailyCompletion(for: drug)
        var xpAwardedForLog = 0
        var dailyXpAwarded = 0
        var milestoneBonus = 0
        var milestoneDay: Int?
        var serverStreak: Int?

        if serverDaily {
            do {
                try await SupabaseManager.ensureSignedInSessionThrowing()
                guard let uid = await SupabaseManager.currentUserId() else {
                    return QuizSessionFinalizeResult(userVisibleError: "Not signed in — can’t sync today’s XP.")
                }
                let outcome = try await SupabaseManager.submitDailyCompletion(
                    userId: uid,
                    drugId: drug.id,
                    correctCount: correctCount,
                    totalQuestions: totalCount
                )
                switch outcome {
                case .success(let award):
                    xpAwardedForLog = award.totalXpAwarded
                    dailyXpAwarded = award.dailyXp
                    milestoneBonus = award.milestoneBonus
                    // The server returns the full ordered list; the *largest* day is the
                    // most user-meaningful one to celebrate (e.g. 14-day overrides 7-day
                    // when both flip on the same completion of a recovered streak).
                    milestoneDay = award.milestones.map(\.day).max()
                    serverStreak = award.streak
                    let dateKey = award.challengeDate ?? DailyChallengeService.shared.assignment?.challengeDateRaw
                    if let dateKey {
                        DailyChallengeService.shared.markServerCompletion(forChallengeDate: dateKey)
                    }
                    await applyServerXPTotalsFromSupabase(userId: uid)
                    if milestoneBonus > 0, let day = milestoneDay {
                        NotificationCenter.default.post(
                            name: .xpBonusAwarded,
                            object: nil,
                            userInfo: ["reason": "\(day)-day streak", "xp": milestoneBonus]
                        )
                    }
                case .alreadyCompleted(let challengeDate, let streak):
                    xpAwardedForLog = 0
                    serverStreak = streak
                    let dateKey = challengeDate ?? DailyChallengeService.shared.assignment?.challengeDateRaw
                    if let dateKey {
                        DailyChallengeService.shared.markServerCompletion(forChallengeDate: dateKey)
                    }
                    await applyServerXPTotalsFromSupabase(userId: uid)
                case .challengeRefreshed(_):
                    await DailyChallengeService.shared.refreshFromServer()
                    await DailyChallengeService.shared.ensureCatalogContainsChallengeDrug()
                    return QuizSessionFinalizeResult(
                        userVisibleError: "The daily drug has refreshed. Pull down to load today's challenge."
                    )
                case .userMismatch:
                    return QuizSessionFinalizeResult(
                        userVisibleError: "Account mismatch — sign out and sign in again, then retry today’s quiz."
                    )
                case .failure(let message):
                    return QuizSessionFinalizeResult(userVisibleError: message)
                }
            } catch {
                return QuizSessionFinalizeResult(userVisibleError: error.localizedDescription)
            }
        } else {
            // No server daily assignment available for this drug — do not award local XP.
            // Server is the sole source of truth for total_xp / weekly_xp; any local
            // increment here would never make it back to the server (the profile sync
            // payload omits XP columns by design) and would be wiped on the next launch
            // refresh. The user can still complete the quiz for spaced-review progress,
            // and a daily challenge that lands later will award XP via the RPC path above.
            xpAwardedForLog = 0
        }

        var scores = drugScores[drug.id] ?? []
        scores.append(pct)
        drugScores[drug.id] = scores
        var sources = drugScoreSources[drug.id] ?? []
        sources.append(source.rawValue)
        drugScoreSources[drug.id] = sources

        var srsState = drugSRSStates[drug.id] ?? inferredInitialSRSState(for: drug.id)
        Self.applySM2(to: &srsState, quizPercent: pct)
        drugSRSStates[drug.id] = srsState
        drugNextReview[drug.id] = Calendar.current.date(byAdding: .day, value: srsState.intervalDays, to: Date()) ?? Date()

        if todayQuiz {
            // Server is the authoritative streak source (via `submit_daily_completion` →
            // `compute_user_streak`). When the RPC returned a streak (success or already-
            // completed paths), adopt it; otherwise leave local streak untouched — the next
            // `refreshAuthoritativeProgressFromServer` will reconcile.
            if let s = serverStreak {
                streak = s
            }
            lastStudyDateString = todayString()
        }

        let sessionSummary = LastDrugQuizSessionSummary(
            drugId: drug.id,
            correctCount: correctCount,
            totalCount: totalCount,
            timestamp: Date().timeIntervalSince1970
        )
        lastDrugQuizSession = sessionSummary
        if todayQuiz || source == .daily {
            lastDailyQuizSession = sessionSummary
        }

        save()
        syncToSupabase(drug: drug, correctCount: correctCount, totalCount: totalCount, quizPercent: pct)
        logQuizAttempt(drug: drug, correctCount: correctCount, totalCount: totalCount, xpAwarded: xpAwardedForLog)

        return QuizSessionFinalizeResult(
            userVisibleError: nil,
            dailyXpAwarded: dailyXpAwarded,
            milestoneBonus: milestoneBonus,
            milestoneDay: milestoneDay
        )
    }

    /// Pulls the user's `public.users` row from Supabase and writes its fields into local state.
    /// Returns `true` when a row was found AND contains meaningful state (display_name set, or any progress).
    /// Callers (AuthView after Apple sign-in, ContentView on cold launch) use the `true` return to skip the
    /// onboarding flow for returning users on new devices / reinstalls.
    ///
    /// XP/streak hydration is **unconditional**: whenever a row exists, `total_xp`, `weekly_xp`, and
    /// `streak` are written from the server so Growth Dashboard and Leaderboard share one source of truth.
    /// The `hasName || hasProgress` decision only gates the onboarding-skip return value and the name
    /// write — not the XP write — so a freshly-renamed account with 0 prior progress still gets the
    /// correct (possibly zero) XP rather than holding stale local cache.
    @discardableResult
    func hydrateFromServerIfNeeded() async -> Bool {
        guard SupabaseManager.isConfiguredForRemote else { return false }
        guard let uid = await SupabaseManager.currentUserId() else { return false }
        let row: SupabaseManager.UserRow?
        do {
            row = try await SupabaseManager.fetchUserProfile(userId: uid)
        } catch {
            #if DEBUG
            print("hydrateFromServerIfNeeded fetch failed: \(error)")
            #endif
            return false
        }
        guard let row else { return false }

        // Unconditionally adopt server XP/streak — this is what fixes Growth showing 0
        // while Leaderboard shows the real XP after a sign-out / sign-in cycle.
        totalXP = row.total_xp
        weeklyXP = row.weekly_xp
        streak = row.streak

        let trimmedName = (row.display_name).trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholderNames: Set<String> = ["", "unknown", "anonymous", "player", "guest"]
        let hasName = !placeholderNames.contains(trimmedName.lowercased())
        let hasProgress = row.total_xp > 0 || row.streak > 0 || row.drugs_studied > 0

        if hasName {
            defaults.set(trimmedName, forKey: "userName")
        }
        if !row.legacy_user_id.isEmpty {
            defaults.set(row.legacy_user_id, forKey: "userID")
        }
        defaults.set(row.is_lifetime, forKey: "isLifetime")
        if let nd = row.naplex_date {
            defaults.set(nd.timeIntervalSince1970, forKey: "naplexDate")
        }
        if let sl = row.student_level, !sl.isEmpty {
            defaults.set(sl, forKey: "studentLevel")
        }
        if let slt = row.student_level_title, !slt.isEmpty {
            defaults.set(slt, forKey: "studentLevelTitle")
        }
        if let remoteFlags = row.flagged_drug_ids, !remoteFlags.isEmpty {
            flaggedDrugIds = Set(remoteFlags)
        }
        if let v = row.daily_reminder_enabled {
            defaults.set(v, forKey: "dailyReminderEnabled")
        }
        if let h = row.daily_reminder_hour {
            defaults.set(h, forKey: "dailyReminderHour")
        }
        if let m = row.daily_reminder_minute {
            defaults.set(m, forKey: "dailyReminderMinute")
        }
        if let theme = row.selected_theme, !theme.isEmpty {
            defaults.set(theme, forKey: "selectedTheme")
        }
        if let hc = row.high_contrast_enabled {
            defaults.set(hc, forKey: "highContrastEnabled")
        }
        if let given = row.apple_given_name, !given.isEmpty {
            defaults.set(given, forKey: "appleGivenName")
        }
        if let sd = row.start_date {
            defaults.set(sd.timeIntervalSince1970, forKey: "startDate")
        }
        save()
        return row.has_completed_onboarding == true || hasName || hasProgress
    }

    /// Lightweight refresh used by views that need to display server-authoritative XP/streak
    /// (Growth Dashboard on appear, foregrounding, etc.). Cheap — single users-row read.
    /// Silent on failure: keeps existing local state rather than zeroing it.
    func refreshAuthoritativeProgressFromServer() async {
        guard SupabaseManager.isConfiguredForRemote else { return }
        guard let uid = await SupabaseManager.currentUserId() else { return }
        do {
            let totals = try await SupabaseManager.fetchUserXPTotals(userId: uid)
            totalXP = totals.total
            weeklyXP = totals.weekly
            save()
        } catch {
            #if DEBUG
            print("refreshAuthoritativeProgressFromServer: \(error)")
            #endif
        }
    }

    private func applyServerXPTotalsFromSupabase(userId: UUID) async {
        do {
            let totals = try await SupabaseManager.fetchUserXPTotals(userId: userId)
            totalXP = totals.total
            weeklyXP = totals.weekly
            save()
        } catch {
            #if DEBUG
            print("applyServerXPTotalsFromSupabase: \(error)")
            #endif
        }
    }

    /// 1…4 when the user has rated; `nil` if unrated (nothing stored).
    func difficultyRating(for drugId: String) -> Int? {
        guard let v = drugDifficultyRatings[drugId], (1...4).contains(v) else { return nil }
        return v
    }

    func setDifficultyRating(_ level: Int, for drugId: String) {
        let v = min(max(level, 1), 4)
        guard drugDifficultyRatings[drugId] != v else { return }
        drugDifficultyRatings[drugId] = v
        save()
    }

    func clearDifficultyRating(for drugId: String) {
        guard drugDifficultyRatings.removeValue(forKey: drugId) != nil else { return }
        save()
    }

    func isDrugFlagged(_ drugId: String) -> Bool {
        flaggedDrugIds.contains(drugId)
    }

    func toggleDrugFlag(_ drugId: String) {
        if flaggedDrugIds.contains(drugId) {
            flaggedDrugIds.remove(drugId)
        } else {
            flaggedDrugIds.insert(drugId)
        }
        save()
    }

    func recordClassQuizAttempt(
        selectedSubCollections: [SubCollection],
        selectedClassNames: [String],
        questionCount: Int,
        correctCount: Int,
        totalCount: Int
    ) {
        let safeTotal = max(totalCount, 1)
        let percent = Int((Double(correctCount) / Double(safeTotal)) * 100)
        let entry = ClassQuizHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            selectedSubCollections: selectedSubCollections,
            selectedClassNames: selectedClassNames,
            questionCount: questionCount,
            correctCount: correctCount,
            totalCount: totalCount,
            scorePercent: percent
        )
        classQuizHistory.insert(entry, at: 0)
        if classQuizHistory.count > 50 {
            classQuizHistory.removeLast(classQuizHistory.count - 50)
        }
        save()
    }

    func averageScore(for drug: Drug, filter: QuizScoreFilter = .all) -> Int {
        let scores = scores(for: drug, filter: filter)
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / scores.count
    }

    func isMastered(_ drug: Drug, filter: QuizScoreFilter = .all) -> Bool {
        let scores = scores(for: drug, filter: filter)
        return scores.count >= 2 && averageScore(for: drug, filter: filter) >= 80
    }

    func isDueForReview(_ drug: Drug) -> Bool {
        guard let next = drugNextReview[drug.id] else { return false }
        return next <= Date()
    }

    func drugsStudied(from drugs: [Drug], filter: QuizScoreFilter = .all) -> [Drug] {
        drugs.filter { !scores(forDrugId: $0.id, filter: filter).isEmpty }
    }

    func drugsForReview(from drugs: [Drug]) -> [Drug] {
        drugs.filter { isDueForReview($0) }
    }

    func scores(for drug: Drug, filter: QuizScoreFilter = .all) -> [Int] {
        scores(forDrugId: drug.id, filter: filter)
    }

    /// Percent from the latest daily-tracked quiz attempt for this drug (most recent appended score with `.daily` source).
    func latestDailyQuizPercent(for drug: Drug) -> Int? {
        let dailyScores = scores(for: drug, filter: .daily)
        return dailyScores.last
    }

    /// Best (highest) daily quiz score recorded for this drug, or `nil` if the user has no daily attempts.
    func bestDailyScore(for drug: Drug) -> Int? {
        scores(for: drug, filter: .daily).max()
    }

    /// Number of daily-source quiz attempts the user has logged for this drug.
    func dailyAttemptCount(for drug: Drug) -> Int {
        scores(for: drug, filter: .daily).count
    }

    /// Drugs (from `drugs`) that have at least one daily-source quiz attempt — used to populate the
    /// Growth Daily Drug Archive sheet.
    func drugsWithDailyAttempts(from drugs: [Drug]) -> [Drug] {
        drugs.filter { !scores(for: $0, filter: .daily).isEmpty }
    }

    private func scores(forDrugId drugId: String, filter: QuizScoreFilter) -> [Int] {
        let scores = drugScores[drugId] ?? []
        guard filter != .all else { return scores }
        guard !scores.isEmpty else { return [] }
        let sources = alignedSources(forDrugId: drugId, scoreCount: scores.count)
        return zip(scores, sources).compactMap { score, source in
            switch filter {
            case .all:
                return score
            case .library:
                // Legacy attempts (pre-source tracking) are treated as library results.
                return (source == .library || source == .unknown) ? score : nil
            case .daily:
                return source == .daily ? score : nil
            }
        }
    }

    private func alignedSources(forDrugId drugId: String, scoreCount: Int) -> [QuizSource] {
        var sources = (drugScoreSources[drugId] ?? []).compactMap(QuizSource.init(rawValue:))
        if sources.count < scoreCount {
            // Backward compatibility: old scores had no source metadata; mark as unknown.
            sources.append(contentsOf: Array(repeating: .unknown, count: scoreCount - sources.count))
        } else if sources.count > scoreCount {
            sources = Array(sources.prefix(scoreCount))
        }
        return sources
    }

    /// The `QuizSource` stored for the user's most recent appended attempt for this drug (aligned with `drugScores`).
    func lastAppendedQuizSource(forDrugId drugId: String) -> QuizSource? {
        let scores = drugScores[drugId] ?? []
        guard !scores.isEmpty else { return nil }
        let sources = alignedSources(forDrugId: drugId, scoreCount: scores.count)
        return sources.last
    }

    /// If `lastDailyQuizSession` was never persisted (older builds) but the latest attempt is tagged `.daily`,
    /// restore it so Growth can render the archive header without forcing another quiz.
    private func repairLastDailyQuizSessionIfNeeded() {
        guard lastDailyQuizSession == nil, let session = lastDrugQuizSession else { return }
        if lastAppendedQuizSource(forDrugId: session.drugId) == .daily {
            lastDailyQuizSession = session
            save()
            return
        }
        // Today's drug can be launched from Library (`QuizSource.library`); if XP was awarded for today's
        // drug, treat the latest session as the daily archive anchor even when the score row says "library".
        let ordered = DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
        if let drug = DrugService.shared.drugs.first(where: { $0.id == session.drugId }),
           isEffectiveTodaysDrug(drug, allDrugs: ordered),
           hasAwardedDailyQuizXPToday() {
            lastDailyQuizSession = session
            save()
        }
    }

    var currentRank: String {
        switch totalXP {
        case 0..<250:       return "Intern"
        case 250..<650:     return "Pharmacy Tech"
        case 650..<2140:    return "Pharmacy Assistant"
        case 2140..<4320:   return "Staff Pharmacist"
        case 4320..<8310:   return "Senior Pharmacist"
        case 8310..<13775:  return "Clinical Pharmacist"
        case 13775..<22090: return "PharmD Candidate"
        case 22090..<27310: return "Board Certified"
        default:            return "Master"
        }
    }

    var rankProgressInfo: (currentXP: Int, currentMin: Int, nextMin: Int, nextRankTitle: String, isMaxRank: Bool) {
        let thresholds: [(rank: String, min: Int)] = [
            ("Intern", 0),
            ("Pharmacy Tech", 250),
            ("Pharmacy Assistant", 650),
            ("Staff Pharmacist", 2140),
            ("Senior Pharmacist", 4320),
            ("Clinical Pharmacist", 8310),
            ("PharmD Candidate", 13775),
            ("Board Certified", 22090),
            ("Master", 27310)
        ]
        guard let idx = thresholds.firstIndex(where: { $0.rank == currentRank }) else {
            return (totalXP, 0, 250, "Pharmacy Tech", false)
        }
        let currentMin = thresholds[idx].min
        if idx + 1 < thresholds.count {
            let next = thresholds[idx + 1]
            let nextTitle: String
            switch next.rank {
            case "Pharmacy Tech":      nextTitle = "Pharmacy Technician"
            case "Pharmacy Assistant": nextTitle = "Pharmacy Assistant"
            case "Staff Pharmacist":   nextTitle = "Staff Pharmacist"
            case "Senior Pharmacist":  nextTitle = "Senior Pharmacist"
            case "Clinical Pharmacist":nextTitle = "Clinical Pharmacist"
            case "PharmD Candidate":   nextTitle = "PharmD Candidate"
            case "Board Certified":    nextTitle = "Board Certified Pharmacist"
            case "Master":             nextTitle = "Master Pharmacist"
            default:                   nextTitle = next.rank
            }
            return (totalXP, currentMin, next.min, nextTitle, false)
        } else {
            return (totalXP, currentMin, currentMin, "Max Rank", true)
        }
    }

    var currentRankDisplayTitle: String {
        switch currentRank {
        case "Intern":               return "Pharmacy Intern"
        case "Pharmacy Tech":        return "Pharmacy Technician"
        case "Pharmacy Assistant":   return "Pharmacy Assistant"
        case "Staff Pharmacist":     return "Staff Pharmacist"
        case "Senior Pharmacist":    return "Senior Pharmacist"
        case "Clinical Pharmacist":  return "Clinical Pharmacist"
        case "PharmD Candidate":     return "PharmD Candidate"
        case "Board Certified":      return "Board Certified Pharmacist"
        case "Master":               return "Master Pharmacist"
        default:                     return currentRank
        }
    }

    /// Maps `currentRank` to `public.users.level` (1…9).
    var rankLevel: Int {
        switch currentRank {
        case "Intern": return 1
        case "Pharmacy Tech": return 2
        case "Pharmacy Assistant": return 3
        case "Staff Pharmacist": return 4
        case "Senior Pharmacist": return 5
        case "Clinical Pharmacist": return 6
        case "PharmD Candidate": return 7
        case "Board Certified": return 8
        case "Master": return 9
        default: return 1
        }
    }

    var userID: String {
        if let existing = defaults.string(forKey: "userID") {
            return existing
        }
        let chars: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let new = String((0..<8).map { _ in chars.randomElement() ?? "A" })
        defaults.set(new, forKey: "userID")
        return new
    }

    func todaysDrugIndex() -> Int {
        let sourceCount = max(
            DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs.count : DrugService.orderedDrugs.count,
            1
        )

        #if DEBUG
        // Dev-only escape hatch for testing specific drugs; never read in Release.
        if defaults.bool(forKey: "devDrugOverrideEnabled") {
            return normalizedIndex(defaults.integer(forKey: "devDrugOverride"), count: sourceCount)
        }
        #endif

        let todayKey = todayString()
        let anchorKey: String
        if let storedAnchor = defaults.string(forKey: Keys.dailyDrugSequenceAnchorDate), !storedAnchor.isEmpty {
            anchorKey = storedAnchor
        } else {
            anchorKey = todayKey
            defaults.set(anchorKey, forKey: Keys.dailyDrugSequenceAnchorDate)
        }

        guard
            let anchorDate = dateFromDayString(anchorKey),
            let todayDate = dateFromDayString(todayKey)
        else {
            return 0
        }

        let daysElapsed = Calendar.current.dateComponents([.day], from: anchorDate, to: todayDate).day ?? 0
        return normalizedIndex(daysElapsed, count: sourceCount)
    }

    private func todayString() -> String {
        Self.dayFormatter.string(from: Date())
    }

    private func yesterdayString() -> String {
        Self.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    private func dateFromDayString(_ value: String) -> Date? {
        Self.dayFormatter.date(from: value)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private func logQuizAttempt(drug: Drug, correctCount: Int, totalCount: Int, xpAwarded: Int) {
        Task {
            await SupabaseManager.ensureAnonymousSession()
            guard let uid = await SupabaseManager.currentUserId() else { return }
            let row = SupabaseManager.QuizAttemptRow(
                user_id: uid,
                drug_id: drug.id,
                correct_count: correctCount,
                total_questions: totalCount,
                xp_awarded: xpAwarded,
                timestamp: Date()
            )
            do {
                try await SupabaseManager.logQuizAttempt(row)
            } catch let firstError {
                // Retry once after a short delay — quiz attempts are best-effort
                // analytics; a second failure is silently discarded in release.
                #if DEBUG
                print("Supabase quiz_attempts insert failed (will retry): \(firstError)")
                #endif
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                do {
                    try await SupabaseManager.logQuizAttempt(row)
                } catch {
                    #if DEBUG
                    print("Supabase quiz_attempts insert (retry failed): \(error)")
                    #endif
                }
            }
        }
    }

    enum DisplayNameError: LocalizedError {
        case taken
        case invalidFormat
        case notAuthenticated
        case tooSoon(unlockDate: Date)

        var errorDescription: String? {
            switch self {
            case .taken: return "Username already taken"
            case .notAuthenticated: return "Sign-in required to change your username"
            case .invalidFormat: return "2\u{2013}20 characters: letters, numbers, spaces only, no consecutive spaces"
            case .tooSoon(let date):
                let fmt = DateFormatter()
                fmt.dateStyle = .long
                fmt.timeStyle = .none
                return "You can change your username again on \(fmt.string(from: date))"
            }
        }
    }

    private func nameHasValidFormat(_ s: String) -> Bool {
        guard (2...20).contains(s.count) else { return false }
        guard s.range(of: "^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$", options: .regularExpression) != nil else { return false }
        return !s.contains("  ")
    }

    /// Validates format locally, then delegates all server-side enforcement
    /// (30-day cooldown, uniqueness, banned-name list) to the change_display_name RPC.
    /// Local UserDefaults is updated optimistically and reverted on any server error.
    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard nameHasValidFormat(trimmed) else { throw DisplayNameError.invalidFormat }

        let previousName = defaults.string(forKey: "userName") ?? ""
        defaults.set(trimmed, forKey: "userName")
        do {
            try await SupabaseManager.changeDisplayName(trimmed)
        } catch SupabaseManager.ChangeDisplayNameError.invalidFormat {
            defaults.set(previousName, forKey: "userName")
            throw DisplayNameError.invalidFormat
        } catch SupabaseManager.ChangeDisplayNameError.banned {
            defaults.set(previousName, forKey: "userName")
            throw DisplayNameError.taken
        } catch SupabaseManager.ChangeDisplayNameError.taken {
            defaults.set(previousName, forKey: "userName")
            throw DisplayNameError.taken
        } catch SupabaseManager.ChangeDisplayNameError.cooldown(let unlockAt) {
            defaults.set(previousName, forKey: "userName")
            throw DisplayNameError.tooSoon(unlockDate: unlockAt)
        } catch SupabaseManager.ChangeDisplayNameError.notAuthenticated {
            defaults.set(previousName, forKey: "userName")
            throw DisplayNameError.notAuthenticated
        } catch {
            defaults.set(previousName, forKey: "userName")
            throw error
        }
    }

    private func syncProfileAndWait() async throws {
        await SupabaseManager.ensureAnonymousSession()
        guard let uid = await SupabaseManager.currentUserId() else { return }
        let profile = buildUserRow(id: uid)
        try await SupabaseManager.upsertUserProfile(profile)
    }

    func syncProfileOnly() {
        Task {
            await SupabaseManager.ensureAnonymousSession()
            guard let uid = await SupabaseManager.currentUserId() else { return }
            let profile = buildUserRow(id: uid)
            do {
                try await SupabaseManager.upsertUserProfile(profile)
            } catch {
                if SupabaseManager.isUniqueViolationError(error) {
                    #if DEBUG
                    print("Supabase profile upsert: display_name already taken (unique violation)")
                    #endif
                } else {
                    #if DEBUG
                    print("Supabase profile upsert: \(error)")
                    #endif
                }
            }
        }
    }

    /// Marks `has_completed_onboarding = true` on the server. Sets a local "needs sync"
    /// flag first so that if the write fails (offline / no session / app killed mid-flight),
    /// `init()` retries it on the next launch instead of leaving the server flag stale.
    func setOnboardingCompleted() {
        defaults.set(true, forKey: Keys.onboardingCompletedNeedsSync)
        Task { await pushOnboardingCompletedWithRetry() }
    }

    /// Pushes the completion flag with bounded retry (1.5s, then 3s backoff). Clears the
    /// local "needs sync" flag on success; leaves it set on failure so the launch-time
    /// flush retries.
    @discardableResult
    private func pushOnboardingCompletedWithRetry() async -> Bool {
        await SupabaseManager.ensureAnonymousSession()
        guard let uid = await SupabaseManager.currentUserId() else { return false }
        let backoffNanoseconds: [UInt64] = [1_500_000_000, 3_000_000_000]
        for attemptIndex in 0..<3 {
            do {
                try await SupabaseManager.upsertOnboardingCompleted(userId: uid)
                defaults.set(false, forKey: Keys.onboardingCompletedNeedsSync)
                return true
            } catch {
                #if DEBUG
                print("setOnboardingCompleted upsert attempt \(attemptIndex + 1)/3: \(error)")
                #endif
                guard attemptIndex + 1 < 3 else { break }
                try? await Task.sleep(nanoseconds: backoffNanoseconds[attemptIndex])
            }
        }
        return false
    }

    private func naplexDateFromDefaults() -> Date? {
        guard let ts = defaults.object(forKey: "naplexDate") as? Double else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private func supabaseProfileCreatedAt() -> Date {
        let key = Keys.profileCreatedAtForSupabase
        if let ts = defaults.object(forKey: key) as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: key)
        return now
    }

    /// Build the client-authoritative subset of the user profile. XP and is_lifetime are
    /// deliberately excluded — those columns are owned by `submit_daily_completion` and
    /// `admin_adjust_user_xp` respectively. `has_completed_onboarding` is also left nil here
    /// (and is therefore omitted from the PATCH body by the synthesized Encodable), so routine
    /// profile syncs never clobber it — it is written only via `setOnboardingCompleted` →
    /// `SupabaseManager.upsertOnboardingCompleted`. See `SupabaseManager.UserProfileSafeRow`.
    private func buildUserRow(id: UUID) -> SupabaseManager.UserProfileSafeRow {
        let appleRaw = defaults.string(forKey: "appleUserID")
        let _ = appleRaw.flatMap { $0.isEmpty ? nil : $0 }
        let rawLevel = defaults.string(forKey: "studentLevel")
        let studentLevelValue = rawLevel.flatMap { $0.isEmpty ? nil : $0 }
        let rawLevelTitle = defaults.string(forKey: "studentLevelTitle")
        let studentLevelTitleValue = rawLevelTitle.flatMap { $0.isEmpty ? nil : $0 }
        let rawTheme = defaults.string(forKey: "selectedTheme")
        let selectedTheme = rawTheme.flatMap { $0.isEmpty ? nil : $0 }
        let rawAppleGiven = defaults.string(forKey: "appleGivenName")
        let appleGiven = rawAppleGiven.flatMap { $0.isEmpty ? nil : $0 }
        let reminderHour = (defaults.object(forKey: "dailyReminderHour") as? Int)
        let reminderMinute = (defaults.object(forKey: "dailyReminderMinute") as? Int)
        let startDate = (defaults.object(forKey: "startDate") as? Double).map { Date(timeIntervalSince1970: $0) }
        return SupabaseManager.UserProfileSafeRow(
            id: id,
            last_active: Date(),
            naplex_date: naplexDateFromDefaults(),
            student_level: studentLevelValue,
            student_level_title: studentLevelTitleValue,
            flagged_drug_ids: Array(flaggedDrugIds),
            daily_reminder_enabled: defaults.bool(forKey: "dailyReminderEnabled"),
            daily_reminder_hour: reminderHour,
            daily_reminder_minute: reminderMinute,
            selected_theme: selectedTheme,
            high_contrast_enabled: defaults.bool(forKey: "highContrastEnabled"),
            apple_given_name: appleGiven,
            start_date: startDate
        )
    }

    private func syncToSupabase(drug: Drug, correctCount: Int, totalCount: Int, quizPercent: Int) {
        Task {
            await SupabaseManager.ensureAnonymousSession()
            guard let uid = await SupabaseManager.currentUserId() else { return }
            let hasQueued = !loadPendingSyncEvents().isEmpty
            #if DEBUG
            if hasQueued {
                print("Supabase pending sync queue non-empty; catch-up will run after this attempt if needed.")
            }
            #endif

            let didSync = await performSupabaseSyncWithRetry(userId: uid, drug: drug)
            if didSync {
                dequeueAfterSuccess(drugId: drug.id)
                await flushPendingSyncQueue(userId: uid, maxDrugs: 10)
            } else {
                enqueuePendingSync(drugId: drug.id)
            }
        }
    }

    /// Exponential backoff between attempts: 1.5s, then 3s (3 tries total).
    private func performSupabaseSyncWithRetry(userId: UUID, drug: Drug) async -> Bool {
        let backoffNanoseconds: [UInt64] = [1_500_000_000, 3_000_000_000]
        for attemptIndex in 0..<3 {
            do {
                try await performSupabaseSync(userId: userId, drug: drug)
                return true
            } catch {
                #if DEBUG
                print("Supabase sync attempt \(attemptIndex + 1)/3 failed: \(error)")
                #endif
                guard attemptIndex + 1 < 3 else { break }
                try? await Task.sleep(nanoseconds: backoffNanoseconds[attemptIndex])
            }
        }
        return false
    }

    private func performSupabaseSync(userId: UUID, drug: Drug) async throws {
        let profile = buildUserRow(id: userId)
        try await SupabaseManager.upsertUserProfile(profile)

        let srs = drugSRSStates[drug.id]
        let progress = SupabaseManager.DrugProgressRow(
            user_id: userId,
            drug_id: drug.id,
            scores: drugScores[drug.id] ?? [],
            next_review: drugNextReview[drug.id],
            updated_at: Date(),
            ease_factor: srs?.easeFactor,
            repetition_number: srs?.repetitionNumber,
            interval_days: srs?.intervalDays
        )
        try await SupabaseManager.upsertDrugProgress(progress)
    }

    // MARK: - Pending sync queue

    private func loadPendingSyncEvents() -> [PendingSyncEvent] {
        guard let data = defaults.data(forKey: Keys.pendingSyncQueueEvents),
              let decoded = try? JSONDecoder().decode([PendingSyncEvent].self, from: data) else { return [] }
        return decoded
    }

    private func savePendingSyncEvents(_ events: [PendingSyncEvent]) {
        if events.isEmpty {
            defaults.removeObject(forKey: Keys.pendingSyncQueueEvents)
            defaults.set(false, forKey: Keys.pendingSyncNeeded)
        } else if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Keys.pendingSyncQueueEvents)
            defaults.set(true, forKey: Keys.pendingSyncNeeded)
        }
    }

    /// If only the legacy boolean is set, seed the queue with one sensible drug (same idea as the old catch-up path).
    private func migrateLegacyPendingSyncIfNeeded() {
        guard defaults.bool(forKey: Keys.pendingSyncNeeded), loadPendingSyncEvents().isEmpty else { return }
        let drug = DrugService.shared.drugs.first(where: { drugScores[$0.id] != nil }) ?? DrugService.shared.drugs.first
        guard let drug else {
            defaults.set(false, forKey: Keys.pendingSyncNeeded)
            return
        }
        enqueuePendingSync(drugId: drug.id)
    }

    private func enqueuePendingSync(drugId: String) {
        var events = loadPendingSyncEvents()
        events.removeAll { $0.drugId == drugId }
        events.append(PendingSyncEvent(drugId: drugId, enqueuedAt: Date().timeIntervalSince1970))
        let cap = 32
        if events.count > cap {
            events = Array(events.suffix(cap))
        }
        savePendingSyncEvents(events)
    }

    private func dequeueAfterSuccess(drugId: String) {
        var events = loadPendingSyncEvents()
        events.removeAll { $0.drugId == drugId }
        savePendingSyncEvents(events)
    }

    /// Drains queued drugs sequentially (each with full retry/backoff), bounded to avoid long blocking.
    private func flushPendingSyncQueue(userId: UUID, maxDrugs: Int) async {
        var processed = 0
        while processed < maxDrugs {
            let events = loadPendingSyncEvents()
            guard let first = events.first else { break }
            guard let drug = DrugService.shared.drugs.first(where: { $0.id == first.drugId }) else {
                dequeueAfterSuccess(drugId: first.drugId)
                processed += 1
                continue
            }
            let ok = await performSupabaseSyncWithRetry(userId: userId, drug: drug)
            if ok {
                dequeueAfterSuccess(drugId: first.drugId)
                processed += 1
            } else {
                break
            }
        }
    }

    // MARK: - SM-2 Spaced Repetition

    private static func sm2Quality(from pct: Int) -> Int {
        switch pct {
        case 85...100: return 5
        case 70..<85:  return 4
        case 50..<70:  return 3
        case 30..<50:  return 2
        default:       return 0
        }
    }

    static func applySM2(to state: inout DrugSRSState, quizPercent: Int) {
        let q = sm2Quality(from: quizPercent)
        let delta = 0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)
        state.easeFactor = max(1.3, state.easeFactor + delta)

        if q < 3 {
            state.repetitionNumber = 0
            state.intervalDays = 1
        } else {
            switch state.repetitionNumber {
            case 0:  state.intervalDays = 1
            case 1:  state.intervalDays = 6
            default: state.intervalDays = min(180, Int((Double(state.intervalDays) * state.easeFactor).rounded()))
            }
            state.repetitionNumber += 1
        }
    }

    private func inferredInitialSRSState(for drugId: String) -> DrugSRSState {
        let scores = drugScores[drugId] ?? []
        guard !scores.isEmpty else {
            return DrugSRSState(repetitionNumber: 0, easeFactor: 2.5, intervalDays: 1)
        }
        let avg = scores.reduce(0, +) / scores.count
        let reps = min(scores.count, 4)
        let ef = max(1.3, 1.3 + (Double(avg) / 100.0) * 1.5)
        return DrugSRSState(repetitionNumber: reps, easeFactor: ef, intervalDays: 1)
    }
}

extension Notification.Name {
    static let xpBonusAwarded = Notification.Name("xpBonusAwarded")
}
