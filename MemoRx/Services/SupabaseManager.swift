import Foundation
import Supabase

/// Observable surface for auth failures. ContentView subscribes and renders a banner
/// when anonymous sign-in or session restore fails. Prior to this, those failures were
/// swallowed in an empty catch, leaving the user silently degraded (no daily challenge,
/// no XP sync, no error message). Calls from non-MainActor code use `await`.
@MainActor
final class AuthStatusObserver: ObservableObject {
    static let shared = AuthStatusObserver()
    @Published var anonAuthFailureMessage: String?

    private init() {}

    func recordFailure(_ message: String) {
        anonAuthFailureMessage = message
    }

    func clear() {
        anonAuthFailureMessage = nil
    }

    /// User taps "Try again" on the banner.
    func retry() {
        clear()
        Task {
            await SupabaseManager.ensureAnonymousSession()
        }
    }
}

/// Central Supabase client and DB helpers. Tables: `users`, `drug_progress`, `drug_submissions`.
enum SupabaseManager {
    /// `false` when plist values are missing, unsubstituted `$(VAR)` placeholders, or the in-app fallback host is in use.
    /// Remote calls are skipped so launch does not block on DNS/timeouts against `supabase.invalid`.
    static let isConfiguredForRemote: Bool = {
        let urlStr = trimmedInfoString("SUPABASE_URL")
        let keyStr = trimmedInfoString("SUPABASE_ANON_KEY")
        guard !urlStr.isEmpty, !keyStr.isEmpty else { return false }
        guard !urlStr.hasPrefix("$("), !keyStr.hasPrefix("$(") else { return false }
        guard let url = URL(string: urlStr),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              host != "supabase.invalid" else { return false }
        return true
    }()

    static let client = makeClient()

    /// Injected via `Config/Supabase.xcconfig` → `Info.plist` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
    private static var supabaseURLString: String {
        trimmedInfoString("SUPABASE_URL")
    }

    private static var supabaseAnonKey: String {
        trimmedInfoString("SUPABASE_ANON_KEY")
    }

    private static func trimmedInfoString(_ key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeClient() -> SupabaseClient {
        let supabaseURL = validatedSupabaseHTTPURL()
        let options = SupabaseClientOptions(
            auth: .init(
                autoRefreshToken: isConfiguredForRemote,
                emitLocalSessionAsInitialSession: true
            )
        )
        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseAnonKey,
            options: options
        )
    }

    /// Supabase Auth builds a local storage key from `supabaseURL.host!` — host must be non-nil (never use `file://` fallback).
    private static func validatedSupabaseHTTPURL() -> URL {
        let trimmed = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$(") {
            #if DEBUG
            print("SUPABASE_URL looks unsubstituted (build setting / xcconfig). Check Config/Supabase.xcconfig and target base configuration.")
            #endif
            return fallbackSupabaseURL()
        }
        if let url = URL(string: trimmed),
           let host = url.host,
           !host.isEmpty,
           url.scheme?.lowercased() == "https" {
            return url
        }
        #if DEBUG
        print("Invalid Supabase URL configuration (need https URL with a host). Falling back to an inert endpoint.")
        #endif
        return fallbackSupabaseURL()
    }

    private static func fallbackSupabaseURL() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "supabase.invalid"
        return components.url ?? URL(string: "https://supabase.invalid")!
    }

    // MARK: - Auth

    static func ensureAnonymousSession() async {
        guard isConfiguredForRemote else {
            #if DEBUG
            print("[Supabase] not configured for remote, skipping session")
            #endif
            return
        }
        do {
            _ = try await client.auth.session
            await AuthStatusObserver.shared.clear()
            return
        } catch {
            // No session yet — fall through to anonymous sign-in attempt.
        }
        do {
            try await client.auth.signInAnonymously()
            await AuthStatusObserver.shared.clear()
        } catch {
            let detail = detailedAPIError(error)
            #if DEBUG
            print("[Supabase] anonymous sign-in failed: \(detail)")
            #endif
            await AuthStatusObserver.shared.recordFailure(
                "Couldn’t reach the server. Daily quiz, XP sync, and leaderboard need a connection. \(detail)"
            )
        }
    }

    /// Use when a request **requires** a JWT so PostgREST runs as `authenticated` (not `anon`).
    /// If anonymous sign-in is disabled in the Supabase project, or the network fails, this throws a clear error.
    static func ensureSignedInSessionThrowing() async throws {
        guard isConfiguredForRemote else {
            throw NSError(
                domain: "MemoRxSupabase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase isn’t configured in this build (URL/key)."]
            )
        }
        do {
            _ = try await client.auth.session
            return
        } catch {
            // No session yet — establish anonymous auth if the project allows it.
        }
        do {
            try await client.auth.signInAnonymously()
        } catch {
            throw NSError(
                domain: "MemoRxSupabase",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    Can’t sign in to Supabase (anonymous auth failed). In the dashboard: Authentication → Providers → enable Anonymous. Then check network and try again.
                    """
                    ,
                    NSUnderlyingErrorKey: error
                ]
            )
        }
        do {
            _ = try await client.auth.session
        } catch {
            throw NSError(
                domain: "MemoRxSupabase",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Signed in anonymously, but no session is available. Try again or restart the app.",
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    private static func detailedAPIError(_ error: Error) -> String {
        var parts: [String] = [error.localizedDescription]
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            parts.append((underlying as NSError).localizedDescription)
        }
        for key in ["message", "error_description", "msg", "hint", "details"] {
            if let s = ns.userInfo[key] as? String, !s.isEmpty, !parts.contains(s) {
                parts.append(s)
            }
        }
        return parts.joined(separator: " — ")
    }

    /// True when `error` (or any wrapped underlying) looks like a network outage —
    /// `NSURLErrorDomain` / `kCFErrorDomainCFNetwork` "not connected / timeout / DNS"
    /// codes. User-facing surfaces use this to collapse framework diagnostics
    /// (e.g. "kCFErrorDomainCFNetwork error -1009") into a clean "you're offline".
    static func isOfflineError(_ error: Error) -> Bool {
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,   // -1009
            NSURLErrorTimedOut,                 // -1001
            NSURLErrorCannotFindHost,           // -1003
            NSURLErrorCannotConnectToHost,      // -1004
            NSURLErrorNetworkConnectionLost,    // -1005
            NSURLErrorDNSLookupFailed,          // -1006
            NSURLErrorInternationalRoamingOff,  // -1018
            NSURLErrorDataNotAllowed            // -1020
        ]
        var current: Error? = error
        while let e = current {
            let ns = e as NSError
            if (ns.domain == NSURLErrorDomain || ns.domain == (kCFErrorDomainCFNetwork as String))
                && offlineCodes.contains(ns.code) {
                return true
            }
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return false
    }

    static func currentUserId() async -> UUID? {
        guard isConfiguredForRemote else { return nil }
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }

    static func signOutCurrentSession() async {
        guard isConfiguredForRemote else { return }
        do {
            try await client.auth.signOut()
        } catch {
            #if DEBUG
            print("Supabase sign out failed: \(error)")
            #endif
        }
    }

    /// Exchanges an Apple `identityToken` for a real Apple-linked Supabase session.
    /// Replaces any prior anonymous session; `currentUserId()` afterward returns the
    /// stable Apple-derived UUID, identical across devices/reinstalls for the same Apple ID.
    static func signInWithApple(idToken: String, nonce: String) async throws {
        guard isConfiguredForRemote else {
            throw NSError(
                domain: "MemoRxSupabase",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: "Supabase isn’t configured in this build (URL/key)."]
            )
        }
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }

    /// Server-side stitch after `signInWithApple` succeeds.
    /// Pass `previousAnonId` if the device had an anonymous session before this sign-in —
    /// the RPC migrates that anon `users` row's XP/streak/etc. and reassigns drug_progress,
    /// quiz_attempts, and daily_completions onto the new Apple-derived `auth.uid()`.
    @discardableResult
    static func claimAppleUser(appleUserId: String, previousAnonId: UUID?) async throws -> ClaimAppleUserOutcome {
        struct Params: Encodable, Sendable {
            let p_apple_user_id: String
            let p_previous_anon_id: UUID?
        }
        let response = try await client.rpc(
            "claim_apple_user",
            params: Params(p_apple_user_id: appleUserId, p_previous_anon_id: previousAnonId)
        ).execute()
        return Self.parseClaimAppleUserData(response.data)
    }

    enum ClaimAppleUserOutcome: Sendable {
        case success(merged: Bool, previousId: UUID?)
        case failure(message: String)
    }

    private static func parseClaimAppleUserData(_ data: Data) -> ClaimAppleUserOutcome {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(message: "Invalid response from claim_apple_user.")
        }
        let success = obj["success"] as? Bool ?? false
        if success {
            let merged = obj["merged"] as? Bool ?? false
            var prev: UUID?
            if let s = obj["previous_id"] as? String { prev = UUID(uuidString: s) }
            return .success(merged: merged, previousId: prev)
        }
        let msg = obj["error"] as? String ?? "Unknown error from claim_apple_user."
        return .failure(message: msg)
    }

    // MARK: - Rows (snake_case matches PostgREST)

    /// Matches `public.users` in `supabase_tables.sql` (including optional `naplex_date` from compatibility alters).
    /// Used for DECODE (leaderboard/profile read). For client-driven WRITES, use `UserProfileSafeRow` —
    /// it intentionally omits server-owned columns so client syncs cannot clobber admin XP adjustments
    /// (`admin_adjust_user_xp`) or admin-granted `is_lifetime` comps.
    struct UserRow: Codable {
        var id: UUID
        var legacy_user_id: String
        var apple_user_id: String?
        var display_name: String
        var total_xp: Int
        var weekly_xp: Int
        var streak: Int
        var level: Int
        var level_title: String
        var drugs_studied: Int
        var is_lifetime: Bool
        var created_at: Date
        var last_active: Date
        var naplex_date: Date?
        var student_level: String?
        var student_level_title: String?
        var flagged_drug_ids: [String]?
        var daily_reminder_enabled: Bool?
        var daily_reminder_hour: Int?
        var daily_reminder_minute: Int?
        var selected_theme: String?
        var high_contrast_enabled: Bool?
        var apple_given_name: String?
        var start_date: Date?
        var has_completed_onboarding: Bool?

        // PostgREST returns Postgres `date` columns (naplex_date, start_date) as "yyyy-MM-dd"
        // with no time component. The Supabase Swift SDK's ISO8601 decoder rejects those
        // strings, throwing a DecodingError that previously made hydrateFromServerIfNeeded
        // return false and re-trigger onboarding on every sign-in.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            legacy_user_id = try c.decodeIfPresent(String.self, forKey: .legacy_user_id) ?? ""
            apple_user_id = try c.decodeIfPresent(String.self, forKey: .apple_user_id)
            display_name = try c.decodeIfPresent(String.self, forKey: .display_name) ?? ""
            total_xp = try c.decodeIfPresent(Int.self, forKey: .total_xp) ?? 0
            weekly_xp = try c.decodeIfPresent(Int.self, forKey: .weekly_xp) ?? 0
            streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
            level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
            level_title = try c.decodeIfPresent(String.self, forKey: .level_title) ?? ""
            drugs_studied = try c.decodeIfPresent(Int.self, forKey: .drugs_studied) ?? 0
            is_lifetime = try c.decodeIfPresent(Bool.self, forKey: .is_lifetime) ?? false
            created_at = try c.decode(Date.self, forKey: .created_at)
            last_active = try c.decode(Date.self, forKey: .last_active)
            naplex_date = Self.decodeDateFlexible(c, forKey: .naplex_date)
            student_level = try c.decodeIfPresent(String.self, forKey: .student_level)
            student_level_title = try c.decodeIfPresent(String.self, forKey: .student_level_title)
            flagged_drug_ids = try c.decodeIfPresent([String].self, forKey: .flagged_drug_ids)
            daily_reminder_enabled = try c.decodeIfPresent(Bool.self, forKey: .daily_reminder_enabled)
            daily_reminder_hour = try c.decodeIfPresent(Int.self, forKey: .daily_reminder_hour)
            daily_reminder_minute = try c.decodeIfPresent(Int.self, forKey: .daily_reminder_minute)
            selected_theme = try c.decodeIfPresent(String.self, forKey: .selected_theme)
            high_contrast_enabled = try c.decodeIfPresent(Bool.self, forKey: .high_contrast_enabled)
            apple_given_name = try c.decodeIfPresent(String.self, forKey: .apple_given_name)
            start_date = Self.decodeDateFlexible(c, forKey: .start_date)
            has_completed_onboarding = try c.decodeIfPresent(Bool.self, forKey: .has_completed_onboarding)
        }

        // Handles both full ISO8601 timestamps and Postgres date-only "yyyy-MM-dd" strings.
        private static func decodeDateFlexible<K: CodingKey>(
            _ c: KeyedDecodingContainer<K>, forKey key: K
        ) -> Date? {
            guard let raw = try? c.decodeIfPresent(String.self, forKey: key), !raw.isEmpty else { return nil }
            if let d = ISO8601DateFormatter().date(from: raw) { return d }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            return df.date(from: raw)
        }
    }

    /// Subset of `public.users` columns that the client is authoritative for.
    /// Columns NOT in this struct are gated by `users_update_lockdown` (column-level
    /// GRANTs + a BEFORE UPDATE trigger) and can only be written by SECURITY DEFINER RPCs.
    /// Keep UpdateBody in lockstep with the migration's GRANT list.
    struct UserProfileSafeRow: Encodable {
        var id: UUID
        var last_active: Date
        var naplex_date: Date?
        var student_level: String?
        var student_level_title: String?
        var flagged_drug_ids: [String]
        var daily_reminder_enabled: Bool
        var daily_reminder_hour: Int?
        var daily_reminder_minute: Int?
        var selected_theme: String?
        var high_contrast_enabled: Bool
        var apple_given_name: String?
        var start_date: Date?
        var has_completed_onboarding: Bool?

        /// PATCH body for upsertUserProfile. Omits `id` because:
        ///   1. PostgreSQL requires table-level UPDATE for ON CONFLICT DO UPDATE,
        ///      but `users_update_lockdown` only grants column-level UPDATE.
        ///   2. `id` is not in the column-level grant list, so including it in the
        ///      SET clause would cause "permission denied for column id of table users".
        /// `id` goes in the .eq() filter instead.
        struct UpdateBody: Encodable {
            var last_active: Date
            var naplex_date: Date?
            var student_level: String?
            var student_level_title: String?
            var flagged_drug_ids: [String]
            var daily_reminder_enabled: Bool
            var daily_reminder_hour: Int?
            var daily_reminder_minute: Int?
            var selected_theme: String?
            var high_contrast_enabled: Bool
            var apple_given_name: String?
            var start_date: Date?
            var has_completed_onboarding: Bool?
        }

        var updateBody: UpdateBody {
            UpdateBody(
                last_active: last_active,
                naplex_date: naplex_date,
                student_level: student_level,
                student_level_title: student_level_title,
                flagged_drug_ids: flagged_drug_ids,
                daily_reminder_enabled: daily_reminder_enabled,
                daily_reminder_hour: daily_reminder_hour,
                daily_reminder_minute: daily_reminder_minute,
                selected_theme: selected_theme,
                high_contrast_enabled: high_contrast_enabled,
                apple_given_name: apple_given_name,
                start_date: start_date,
                has_completed_onboarding: has_completed_onboarding
            )
        }
    }

    struct DrugProgressRow: Codable {
        var user_id: UUID
        var drug_id: String
        var scores: [Int]
        var next_review: Date?
        var updated_at: Date
    }

    struct DrugSubmissionRow: Encodable {
        var user_id: UUID
        var drug_name: String
        var reason: String?
        var created_at: Date
    }

    struct QuizAttemptRow: Encodable {
        var user_id: UUID
        var drug_id: String
        var correct_count: Int
        var total_questions: Int
        var xp_awarded: Int
        var timestamp: Date
    }

    struct LeaderboardUserRow: Decodable {
        /// Matches DB type: `users.id` may be `text` in some projects; PostgREST JSON can be string or UUID-shaped.
        var id: String
        var legacy_user_id: String
        var display_name: String?
        var total_xp: Int
        var weekly_xp: Int
        var streak: Int
        var level_title: String
        var drugs_studied: Int
        var student_level: String?

        enum CodingKeys: String, CodingKey {
            case id, legacy_user_id, display_name, total_xp, weekly_xp, streak, level_title, drugs_studied, student_level
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let uuid = try? c.decode(UUID.self, forKey: .id) {
                id = uuid.uuidString
            } else if let s = try? c.decode(String.self, forKey: .id) {
                id = s
            } else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Expected id as UUID or string.")
            }
            legacy_user_id = try c.decodeIfPresent(String.self, forKey: .legacy_user_id) ?? ""
            display_name = try c.decodeIfPresent(String.self, forKey: .display_name) ?? "Unknown"
            total_xp = Self.decodeInt(c, key: .total_xp)
            weekly_xp = Self.decodeInt(c, key: .weekly_xp)
            streak = Self.decodeInt(c, key: .streak)
            level_title = try c.decodeIfPresent(String.self, forKey: .level_title) ?? ""
            drugs_studied = Self.decodeInt(c, key: .drugs_studied)
            student_level = try c.decodeIfPresent(String.self, forKey: .student_level)
        }

        private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int {
            if let v = try? c.decode(Int.self, forKey: key) { return v }
            if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
            return 0
        }
    }

    // MARK: - Writes

    /// Returns `true` when `error` is a Postgres unique-violation (code 23505).
    static func isUniqueViolationError(_ error: Error) -> Bool {
        let msg = (error as NSError).debugDescription + error.localizedDescription
        return msg.contains("23505") || msg.contains("unique_violation") || msg.contains("duplicate key")
    }

    /// Client-side profile sync. Sends only the columns the client owns, so admin XP
    /// adjustments and `is_lifetime` grants survive every quiz-finish sync.
    ///
    /// Uses PATCH (.update + .eq) instead of upsert: POST ?on_conflict=id generates
    /// INSERT...ON CONFLICT DO UPDATE, which PostgreSQL requires table-level UPDATE
    /// for — but `users_update_lockdown` revoked table-level UPDATE and replaced it
    /// with column-level grants (which only satisfy plain UPDATE statements).
    /// The row always exists after `handle_new_auth_user` fires at sign-up.
    static func upsertUserProfile(_ row: UserProfileSafeRow) async throws {
        try await client
            .from("users")
            .update(row.updateBody)
            .eq("id", value: row.id)
            .execute()
    }

    static func upsertOnboardingCompleted(userId: UUID) async throws {
        struct Payload: Encodable { let has_completed_onboarding: Bool }
        try await client
            .from("users")
            .update(Payload(has_completed_onboarding: true))
            .eq("id", value: userId)
            .execute()
    }

    static func upsertDrugProgress(_ row: DrugProgressRow) async throws {
        try await client
            .from("drug_progress")
            .upsert(row, onConflict: "user_id,drug_id")
            .execute()
    }

    static func insertDrugSubmission(_ row: DrugSubmissionRow) async throws {
        try await client
            .from("drug_submissions")
            .insert(row)
            .execute()
    }

    static func logQuizAttempt(_ row: QuizAttemptRow) async throws {
        try await client
            .from("quiz_attempts")
            .insert(row)
            .execute()
    }

    /// Optional hard-delete. May be blocked by RLS depending on project policies.
    static func deleteUserProfile(userId: UUID) async throws {
        try await client
            .from("users")
            .delete()
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Reads

    static func fetchRemoteDrugs() async throws -> [Drug] {
        guard isConfiguredForRemote else { return [] }

        await ensureAnonymousSession()

        return try await client
            .from("drugs")
            .select()
            .execute()
            .value
    }

    static func fetchRemoteClassQuizGuides() async throws -> [ClassQuizGuide] {
        guard isConfiguredForRemote else { return [] }

        await ensureAnonymousSession()

        // Prefer stable table names; `class_quizzes` is optional (see `supabase_tables.sql`) and omitted here to avoid noisy failures when absent.
        let tableCandidates = ["class_quiz_guides", "class_quiz_content"]
        var lastError: Error?

        for table in tableCandidates {
            do {
                let rows: [ClassQuizGuide] = try await client
                    .from(table)
                    .select()
                    .execute()
                    .value
                if !rows.isEmpty {
                    return rows
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    static func fetchLeaderboard(limit: Int = 20) async throws -> [LeaderboardUserRow] {
        guard isConfiguredForRemote else { return [] }

        // Auth precheck — collapse offline failures to a clean user-facing error.
        // The underlying NSError from `ensureSignedInSessionThrowing` includes a
        // developer-facing remediation paragraph that we deliberately keep out of
        // the UI in Release.
        do {
            try await ensureSignedInSessionThrowing()
        } catch {
            #if DEBUG
            print("[SupabaseManager.fetchLeaderboard] auth precheck failed: \(detailedAPIError(error))")
            #endif
            throw leaderboardUserFacingError(from: [error])
        }

        struct LeaderboardQueryCandidate {
            let label: String
            let table: String
            let select: String
            let orderBy: String
        }

        // The `leaderboard_public` view is the only valid leaderboard source. The previous
        // fallbacks to `public.users` returned a single row under own-row RLS and looked like
        // a successful query — a silently wrong "you're alone on the leaderboard" state.
        let candidates: [LeaderboardQueryCandidate] = [
            .init(
                label: "leaderboard_public · weekly_xp",
                table: "leaderboard_public",
                select: "id, legacy_user_id, display_name, total_xp, weekly_xp, streak, level_title, drugs_studied, student_level",
                orderBy: "weekly_xp"
            ),
            // Tolerated only if the view predates the weekly_xp column.
            .init(
                label: "leaderboard_public · total_xp only",
                table: "leaderboard_public",
                select: "id, legacy_user_id, display_name, total_xp, streak, level_title, drugs_studied, student_level",
                orderBy: "total_xp"
            )
        ]

        var failures: [(label: String, error: Error)] = []

        for candidate in candidates {
            do {
                let rows: [LeaderboardUserRow] = try await client
                    .from(candidate.table)
                    .select(candidate.select)
                    .order(candidate.orderBy, ascending: false)
                    .limit(limit)
                    .execute()
                    .value
                return rows
            } catch {
                failures.append((candidate.label, error))
            }
        }

        // All candidates failed. Surface a friendly message; dump the full
        // diagnostic (including the SQL grant remediation that used to leak
        // into the UI) only to the DEBUG console.
        #if DEBUG
        let diagnostic = failures
            .map { "• \($0.label): \(detailedAPIError($0.error))" }
            .joined(separator: "\n")
        print("""
        [SupabaseManager.fetchLeaderboard] all candidates failed:
        \(diagnostic)

        If you see "permission denied" or JWT/RLS errors, run in Supabase SQL:
          grant select on public.leaderboard_public to authenticated, anon;
        """)
        #endif

        throw leaderboardUserFacingError(from: failures.map(\.error))
    }

    /// Friendly NSError for the Leaderboard view. Returns an offline-flavored
    /// message when every failure looks like a network outage; otherwise a
    /// generic "couldn't load right now" message. Developer details are
    /// printed to the DEBUG console at the throw site, never embedded here.
    private static func leaderboardUserFacingError(from errors: [Error]) -> NSError {
        let allOffline = !errors.isEmpty && errors.allSatisfy { isOfflineError($0) }
        if allOffline {
            return NSError(
                domain: "MemoRxSupabase",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "You’re offline. Connect to the internet and try again."]
            )
        }
        return NSError(
            domain: "MemoRxSupabase",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Couldn’t load the leaderboard right now. Please try again."]
        )
    }

    /// Returns the current user's `leaderboard_public` row paired with their 1-based rank
    /// (by `weekly_xp` desc). Used to render a floating standalone card for users outside
    /// the top-N window. Returns `nil` if the user has no row in the view yet (e.g. no quiz
    /// taken since signup) or if remote access is disabled.
    static func fetchUserLeaderboardEntry(legacyUserId: String) async throws -> (entry: LeaderboardUserRow, rank: Int)? {
        guard isConfiguredForRemote else { return nil }
        try await ensureSignedInSessionThrowing()

        let trimmedId = legacyUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }

        let selectColumns = "id, legacy_user_id, display_name, total_xp, weekly_xp, streak, level_title, drugs_studied, student_level"

        let rows: [LeaderboardUserRow] = try await client
            .from("leaderboard_public")
            .select(selectColumns)
            .eq("legacy_user_id", value: trimmedId)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }

        let aboveResponse = try await client
            .from("leaderboard_public")
            .select("id", head: true, count: .exact)
            .gt("weekly_xp", value: row.weekly_xp)
            .execute()
        let aboveCount = aboveResponse.count ?? 0
        return (row, aboveCount + 1)
    }

    // Fix #7: Look up standalone leaderboard entry by Supabase auth UUID.
    // The old legacyUserId overload could silently return nil for Apple-only
    // users whose legacy_user_id was never set (no prior anonymous session).
    static func fetchUserLeaderboardEntry(supabaseUserId: UUID) async throws -> (entry: LeaderboardUserRow, rank: Int)? {
        guard isConfiguredForRemote else { return nil }
        try await ensureSignedInSessionThrowing()

        let selectColumns = "id, legacy_user_id, display_name, total_xp, weekly_xp, streak, level_title, drugs_studied, student_level"
        let rows: [LeaderboardUserRow] = try await client
            .from("leaderboard_public")
            .select(selectColumns)
            .eq("id", value: supabaseUserId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }

        let aboveResponse = try await client
            .from("leaderboard_public")
            .select("id", head: true, count: .exact)
            .gt("weekly_xp", value: row.weekly_xp)
            .execute()
        let aboveCount = aboveResponse.count ?? 0
        return (row, aboveCount + 1)
    }

    /// Returns the user's `public.users` row, or `nil` if no row exists for this id.
    /// Used after Apple sign-in (and on cold launch) to detect returning users and skip onboarding.
    static func fetchUserProfile(userId: UUID) async throws -> UserRow? {
        let rows: [UserRow] = try await client
            .from("users")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func fetchIsLifetime(userId: UUID) async -> Bool? {
        struct Row: Decodable { let is_lifetime: Bool }
        do {
            let rows: [Row] = try await client
                .from("users")
                .select("is_lifetime")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            return rows.first?.is_lifetime ?? false
        } catch {
            #if DEBUG
            print("[SupabaseManager] fetchIsLifetime error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Daily challenge (server-authoritative)

    private struct MemoEmptyRPCParams: Encodable, Sendable {}

    struct SubmitDailyCompletionParams: Encodable, Sendable {
        let p_user_id: UUID
        let p_drug_id: String
        let p_correct_count: Int
        let p_total_questions: Int
    }

    struct MilestoneHit: Sendable, Equatable {
        let day: Int
        let xp: Int
    }

    struct SubmitDailyCompletionAward: Sendable, Equatable {
        let totalXpAwarded: Int
        let dailyXp: Int
        let milestoneBonus: Int
        let milestones: [MilestoneHit]
        let streak: Int
        let challengeDate: String?
    }

    enum SubmitDailyCompletionOutcome: Sendable {
        case success(SubmitDailyCompletionAward)
        case alreadyCompleted(challengeDate: String?, streak: Int)
        case challengeRefreshed(expectedDrugId: String)
        case userMismatch
        case failure(message: String)
    }

    /// Returns `nil` when the RPC responds with JSON `null` or missing `drug_id`.
    static func fetchCurrentChallengeAssignment() async throws -> ServerDailyAssignment? {
        let response = try await client.rpc("get_current_challenge", params: MemoEmptyRPCParams()).execute()
        return Self.parseChallengeAssignmentData(response.data)
    }

    static func submitDailyCompletion(
        userId: UUID,
        drugId: String,
        correctCount: Int,
        totalQuestions: Int
    ) async throws -> SubmitDailyCompletionOutcome {
        let params = SubmitDailyCompletionParams(
            p_user_id: userId,
            p_drug_id: drugId,
            p_correct_count: correctCount,
            p_total_questions: totalQuestions
        )
        let response = try await client.rpc("submit_daily_completion", params: params).execute()
        return Self.parseSubmitDailyCompletionData(response.data)
    }

    /// Reads authoritative XP from `public.users` after RPC awards or admin adjustments.
    static func fetchUserXPTotals(userId: UUID) async throws -> (total: Int, weekly: Int) {
        struct Row: Decodable {
            var total_xp: Int
            var weekly_xp: Int
        }
        let rows: [Row] = try await client
            .from("users")
            .select("total_xp, weekly_xp")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else {
            throw NSError(
                domain: "MemoRxSupabase",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "No user row when fetching XP totals."]
            )
        }
        return (row.total_xp, row.weekly_xp)
    }

    private static func parseChallengeAssignmentData(_ data: Data) -> ServerDailyAssignment? {
        if data.isEmpty { return nil }
        guard let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed != "null"
        else {
            return nil
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let drugId = obj["drug_id"] as? String, !drugId.isEmpty else { return nil }

        // `get_current_challenge` returns the date under `current_challenge_date`.
        // `challenge_date` is accepted as a fallback for any older RPC build.
        let dateStr: String
        if let s = obj["current_challenge_date"] as? String, !s.isEmpty {
            dateStr = s
        } else if let s = obj["challenge_date"] as? String, !s.isEmpty {
            dateStr = s
        } else {
            return nil
        }

        let title = obj["title"] as? String
        let difficulty = obj["difficulty"] as? String
        let xpBase: Int
        if let n = obj["xp_base"] as? Int {
            xpBase = n
        } else if let num = obj["xp_base"] as? NSNumber {
            xpBase = num.intValue
        } else {
            xpBase = 50
        }

        return ServerDailyAssignment(
            challengeDateRaw: dateStr,
            drugId: drugId,
            title: title,
            difficulty: difficulty,
            xpBase: xpBase
        )
    }

    private static func parseInt(_ obj: [String: Any], key: String, default fallback: Int = 0) -> Int {
        if let n = obj[key] as? Int { return n }
        if let num = obj[key] as? NSNumber { return num.intValue }
        return fallback
    }

    private static func parseSubmitDailyCompletionData(_ data: Data) -> SubmitDailyCompletionOutcome {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(message: "Invalid response from submit_daily_completion.")
        }
        let success = obj["success"] as? Bool ?? false
        let ch = obj["challenge_date"] as? String

        if success {
            let totalXp = parseInt(obj, key: "xp_awarded")
            let dailyXp = parseInt(obj, key: "daily_xp", default: totalXp)
            let milestoneBonus = parseInt(obj, key: "milestone_bonus")
            let streak = parseInt(obj, key: "streak")

            var milestones: [MilestoneHit] = []
            if let arr = obj["milestones"] as? [[String: Any]] {
                for entry in arr {
                    let day = parseInt(entry, key: "day")
                    let xp = parseInt(entry, key: "xp")
                    if day > 0 { milestones.append(MilestoneHit(day: day, xp: xp)) }
                }
            }

            return .success(SubmitDailyCompletionAward(
                totalXpAwarded: totalXp,
                dailyXp: dailyXp,
                milestoneBonus: milestoneBonus,
                milestones: milestones,
                streak: streak,
                challengeDate: ch
            ))
        }

        let err = (obj["error"] as? String)?.lowercased() ?? ""
        switch err {
        case "already_completed":
            return .alreadyCompleted(challengeDate: ch, streak: parseInt(obj, key: "streak"))
        case "drug_not_todays_challenge":
            let expected = (obj["expected_drug_id"] as? String) ?? ""
            return .challengeRefreshed(expectedDrugId: expected)
        case "user_mismatch":
            return .userMismatch
        default:
            let msg = obj["error"] as? String ?? "Unknown error from submit_daily_completion."
            return .failure(message: msg)
        }
    }

    // MARK: - Reset progress (server-authoritative)

    /// SECURITY DEFINER RPC: durably wipes the caller's progress on the server
    /// (drug_progress, quiz_attempts, daily_completions, milestone claims, XP totals).
    /// Required because `daily_completions` has no DELETE RLS policy.
    static func resetMyProgress() async throws {
        struct EmptyParams: Encodable, Sendable {}
        _ = try await client.rpc("reset_my_progress", params: EmptyParams()).execute()
    }

    // MARK: - Account deletion (App Store Guideline 5.1.1(v))

    /// SECURITY DEFINER RPC: deletes the caller's `public.users` row and every
    /// owned row in `drug_progress`, `quiz_attempts`, `drug_submissions`,
    /// `daily_completions`, and `user_milestone_claims`, then deletes the
    /// `auth.users` row so the Apple-derived UID can never sign back in.
    /// After this returns, the active session is invalid; callers should sign out
    /// locally and route back to AuthView.
    static func deleteMyAccount() async throws {
        struct EmptyParams: Encodable, Sendable {}
        _ = try await client.rpc("delete_my_account", params: EmptyParams()).execute()
    }

    // MARK: - Display name availability

    /// Calls the is_display_name_available SECURITY DEFINER RPC which reads the full
    // users table (bypasses per-user RLS) and also checks banned_usernames.
    // Prior implementation queried users directly; RLS (auth.uid() = id) made it
    // only see the caller's own row, reporting every other name as "Available".
    static func isDisplayNameAvailable(_ name: String) async throws -> Bool {
        guard isConfiguredForRemote else { return true }
        struct Params: Encodable { var p_name: String }
        let result: Bool = try await client
            .rpc("is_display_name_available", params: Params(p_name: name))
            .execute()
            .value
        return result
    }

    // ── Fix #3: server-authoritative display name change ─────────────────────
    // Replaces the direct users PATCH. The SECURITY DEFINER RPC enforces format,
    // 30-day cooldown, banned-name list, and uniqueness — none of which could be
    // bypassed by callers with a direct PATCH via the REST API before this fix.

    enum ChangeDisplayNameError: Error {
        case notAuthenticated
        case invalidFormat
        case banned
        case cooldown(unlockAt: Date)
        case taken
    }

    static func changeDisplayName(_ name: String) async throws {
        guard isConfiguredForRemote else { return }
        await ensureAnonymousSession()
        struct Params: Encodable { var p_name: String }
        let data = try await client
            .rpc("change_display_name", params: Params(p_name: name))
            .execute()
            .data
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "MemoRx", code: 100,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response from change_display_name."])
        }
        let success = obj["success"] as? Bool ?? false
        guard !success else { return }
        switch obj["error"] as? String ?? "" {
        case "invalid_format":    throw ChangeDisplayNameError.invalidFormat
        case "banned":            throw ChangeDisplayNameError.banned
        case "name_taken":        throw ChangeDisplayNameError.taken
        case "not_authenticated": throw ChangeDisplayNameError.notAuthenticated
        case "cooldown":
            let raw = obj["unlock_at"] as? String ?? ""
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            let date = fmt.date(from: raw) ?? Date().addingTimeInterval(30 * 24 * 60 * 60)
            throw ChangeDisplayNameError.cooldown(unlockAt: date)
        default:
            throw NSError(domain: "MemoRx", code: 101,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't update username."])
        }
    }

    // MARK: - Display name cooldown

    static func fetchDisplayNameUpdatedAt(userId: UUID) async throws -> Date? {
        guard isConfiguredForRemote else { return nil }
        struct Row: Decodable { var display_name_updated_at: Date? }
        let rows: [Row] = try await client
            .from("users")
            .select("display_name_updated_at")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.display_name_updated_at
    }

    // MARK: - Username reports

    static func insertUsernameReport(reporterId: UUID, reportedId: UUID, reportedName: String) async throws {
        struct ReportRow: Encodable {
            var reporter_id: UUID
            var reported_id: UUID
            var reported_name: String
        }
        try await client
            .from("username_reports")
            .insert(ReportRow(reporter_id: reporterId, reported_id: reportedId, reported_name: reportedName))
            .execute()
    }

}
