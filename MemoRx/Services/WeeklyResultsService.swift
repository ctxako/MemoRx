import Foundation
import Supabase

/// Snapshot of a single past week's leaderboard placement for the signed-in user.
/// Backed by `public.weekly_results` (RLS: own-rows-only SELECT).
struct WeeklyResultRow: Identifiable, Decodable, Hashable {
    let weekStartDate: Date
    let rank: Int
    let xp: Int

    var id: String { Self.isoFormatter.string(from: weekStartDate) }

    enum CodingKeys: String, CodingKey {
        case weekStartDate = "week_start_date"
        case rank, xp
    }

    init(weekStartDate: Date, rank: Int, xp: Int) {
        self.weekStartDate = weekStartDate
        self.rank = rank
        self.xp = xp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dateString = try c.decode(String.self, forKey: .weekStartDate)
        guard let date = Self.isoFormatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .weekStartDate,
                in: c,
                debugDescription: "Expected ISO yyyy-MM-dd date, got \(dateString)"
            )
        }
        weekStartDate = date
        rank = Self.decodeInt(c, key: .rank)
        xp = Self.decodeInt(c, key: .xp)
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s) { return i }
        return 0
    }

    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

extension SupabaseManager {
    /// Past weekly placements for the signed-in user, most-recent first. RLS scopes the
    /// query to `auth.uid()` server-side, so callers never need to pass the user id.
    static func fetchWeeklyResults() async throws -> [WeeklyResultRow] {
        guard isConfiguredForRemote else { return [] }
        try await ensureSignedInSessionThrowing()

        let rows: [WeeklyResultRow] = try await client
            .from("weekly_results")
            .select("week_start_date, rank, xp")
            .order("week_start_date", ascending: false)
            .execute()
            .value
        return rows
    }
}

@MainActor
final class WeeklyResultsService: ObservableObject {
    @Published private(set) var rows: [WeeklyResultRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    func load() async {
        isLoading = true
        loadError = nil
        do {
            rows = try await SupabaseManager.fetchWeeklyResults()
        } catch {
            let uid = await SupabaseManager.currentUserId()
            SentryReporting.captureSupabaseError(
                error,
                operation: "weekly_results.fetch",
                userId: uid
            )
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
