import SwiftUI

struct LeaderboardEntry: Identifiable {
    let id: String
    let userName: String
    let userID: String
    let totalXP: Int
    let weeklyXP: Int
    let streak: Int
    let levelTitle: String
    let drugsStudied: Int
    let accountYear: String?
}

struct LeaderboardView: View {
    @Environment(\.appTheme) private var theme
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var countdownText = ""
    @State private var countdownTimer: Timer?
    @State private var showResetInfo = false
    @State private var standaloneUserEntry: LeaderboardEntry?
    @State private var standaloneUserRank: Int?
    @State private var currentUserSupabaseId: String = ""
    @AppStorage("appleUserID") private var appleUserID = ""
    @State private var showAuthSheet = false
    private let progress = UserProgressService.shared

    private var currentUserIndex: Int? {
        entries.firstIndex { $0.id == currentUserSupabaseId }
    }

    /// True when the current user is already visible in `entries`. In that case we don't
    /// need a floating standalone card.
    private var currentUserInTopList: Bool {
        currentUserIndex != nil
    }

    @State private var reportTarget: LeaderboardEntry?
    @State private var showReportConfirmation = false
    @State private var reportResultMessage: String?
    @State private var showReportResult = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading leaderboard...")
                            .font(theme.appFont(14))
                            .foregroundStyle(.secondary)
                    }
                } else if let err = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Couldn’t load leaderboard")
                            .font(theme.appFont(18, weight: .semibold))
                        Text(err)
                            .font(theme.appFont(13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await fetchLeaderboard() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                } else if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("No scores yet")
                            .font(theme.appFont(18, weight: .semibold))
                        Text("Complete a quiz to sync your profile — pull to refresh after playing.")
                            .font(theme.appFont(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        showResetInfo.toggle()
                                                    }
                                                } label: {
                                                    Image(systemName: "info.circle")
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(Color(hex: "00d4ff"))
                                                }
                                                .buttonStyle(.plain)
                                                .minimumHitTarget()

                                                Text(countdownText)
                                                    .font(theme.appFont(13, weight: .medium))
                                                    .foregroundStyle(Color(.label))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(.systemGray6))
                                            .clipShape(Capsule())

                                            if showResetInfo {
                                                Text("Weekly leaderboard XP resets every Monday at 4:00 AM Eastern Time (America/New_York). The timer below is from your device clock for display only.\nDaily challenge XP is awarded by the server when you finish today's assigned drug quiz.")
                                                    .font(theme.appFont(12))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 8)
                                                    .background(Color(.systemGray6))
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 4)

                                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                        LeaderboardRowView(
                                            rank: index + 1,
                                            entry: entry,
                                            isCurrentUser: entry.id == currentUserSupabaseId
                                        )
                                        .id(entry.id)
                                        .contextMenu {
                                            if entry.id != currentUserSupabaseId {
                                                Button(role: .destructive) {
                                                    reportTarget = entry
                                                    showReportConfirmation = true
                                                } label: {
                                                    Label("Report Username", systemImage: "flag")
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            if !currentUserInTopList,
                               let entry = standaloneUserEntry,
                               let rank = standaloneUserRank {
                                VStack(spacing: 0) {
                                    Divider()
                                    LeaderboardRowView(
                                        rank: rank,
                                        entry: entry,
                                        isCurrentUser: true
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                }
                                .background(Color.appBackground)
                            } else if !currentUserInTopList && appleUserID.isEmpty {
                                VStack(spacing: 0) {
                                    Divider()
                                    Button {
                                        showAuthSheet = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "applelogo")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color(.label))
                                            Text("Sign in with Apple to appear on the leaderboard")
                                                .font(theme.appFont(14, weight: .medium))
                                                .foregroundStyle(Color(.label))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .background(Color.appBackground)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task { await fetchLeaderboard() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(MemoToolbarPillMetrics.iconFont)
                            .foregroundStyle(Color(.label))
                            .padding(.horizontal, MemoToolbarPillMetrics.horizontalPadding)
                            .padding(.vertical, MemoToolbarPillMetrics.verticalPadding)
                            .topBarPillChrome()
                    }
                    .minimumHitTarget()
                }
            }
            .task {
                await fetchLeaderboard()
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthView()
            }
            .alert(
                reportTarget.map { "Report \u{201C}\($0.userName)\u{201D}?" } ?? "Report Username?",
                isPresented: $showReportConfirmation
            ) {
                Button("Report", role: .destructive) { Task { await submitReport() } }
                Button("Cancel", role: .cancel) { reportTarget = nil }
            } message: {
                Text("This username will be flagged for admin review. The player keeps their score.")
            }
            .alert("Report", isPresented: $showReportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportResultMessage ?? "")
        }
        .onAppear {
                updateCountdown()
                countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    updateCountdown()
                }
            }
            .onDisappear {
                countdownTimer?.invalidate()
                countdownTimer = nil
            }
    }

    private func updateCountdown() {
        let now = Date()
        let tz = TimeZone(identifier: "America/New_York") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let weekday = cal.component(.weekday, from: now)
        var daysAhead = 0
        if weekday == 2 {
            let hour = cal.component(.hour, from: now)
            daysAhead = hour < 4 ? 0 : 7
        } else if weekday == 1 {
            daysAhead = 1
        } else {
            daysAhead = (9 - weekday) % 7
            if daysAhead == 0 { daysAhead = 7 }
        }
        let dayStart = cal.dateComponents([.year, .month, .day], from: now)
        guard let baseDay = cal.date(from: dayStart) else {
            countdownText = ""
            return
        }
        guard var target = cal.date(byAdding: .day, value: daysAhead, to: baseDay) else {
            countdownText = ""
            return
        }
        target = cal.date(bySettingHour: 4, minute: 0, second: 0, of: target) ?? target
        if target <= now {
            target = cal.date(byAdding: .day, value: 7, to: target) ?? target
        }
        let secs = Int(target.timeIntervalSince(now))
        guard secs > 0 else { countdownText = "Resetting..."; return }
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        if d > 0 {
            countdownText = "Weekly reset in \(d)d \(h)h \(m)m"
        } else if h > 0 {
            countdownText = "Weekly reset in \(h)h \(m)m"
        } else {
            countdownText = "Weekly reset in \(m)m"
        }
    }

    @MainActor
    private func submitReport() async {
        guard let target = reportTarget else { return }
        guard let reporterId = await SupabaseManager.currentUserId() else { reportTarget = nil; return }
        guard let reportedId = UUID(uuidString: target.id) else { reportTarget = nil; return }
        do {
            try await SupabaseManager.insertUsernameReport(
                reporterId: reporterId,
                reportedId: reportedId,
                reportedName: target.userName
            )
            reportResultMessage = "Report submitted. Thank you."
        } catch {
            if SupabaseManager.isUniqueViolationError(error) {
                reportResultMessage = "You\u{2019}ve already reported this user."
            } else {
                reportResultMessage = "Couldn\u{2019}t submit report. Please try again."
            }
        }
        reportTarget = nil
        showReportResult = true
    }

    @MainActor
    func fetchLeaderboard() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            if currentUserSupabaseId.isEmpty,
               let uid = await SupabaseManager.currentUserId() {
                currentUserSupabaseId = uid.uuidString
            }
            let rows = try await SupabaseManager.fetchLeaderboard(limit: 20)
            entries = rows
                .filter { row in
                    let name = row.display_name ?? ""
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty && !trimmed.localizedCaseInsensitiveContains("signed out")
                }
                .map(Self.makeEntry)

            await refreshStandaloneEntryIfNeeded()
        } catch {
            entries = []
            standaloneUserEntry = nil
            standaloneUserRank = nil
            loadError = error.localizedDescription
            #if DEBUG
            print("Leaderboard fetch error: \(error)")
            #endif
            let uid = await SupabaseManager.currentUserId()
            SentryReporting.captureSupabaseError(
                error,
                operation: "leaderboard_public.fetch",
                userId: uid
            )
        }
    }

    @MainActor
    private func refreshStandaloneEntryIfNeeded() async {
        guard currentUserIndex == nil else {
            standaloneUserEntry = nil
            standaloneUserRank = nil
            return
        }
        // Use the Supabase auth UUID (already fetched into currentUserSupabaseId).
        // The old legacyUserId lookup silently returned nil for Apple-only users
        // whose legacy_user_id was never populated.
        guard let uid = UUID(uuidString: currentUserSupabaseId) else {
            standaloneUserEntry = nil
            standaloneUserRank = nil
            return
        }
        do {
            if let pair = try await SupabaseManager.fetchUserLeaderboardEntry(supabaseUserId: uid) {
                standaloneUserEntry = Self.makeEntry(from: pair.entry)
                standaloneUserRank = pair.rank
            } else {
                standaloneUserEntry = nil
                standaloneUserRank = nil
            }
        } catch {
            standaloneUserEntry = nil
            standaloneUserRank = nil
            #if DEBUG
            print("Standalone rank fetch error: \(error)")
            #endif
            let uid = await SupabaseManager.currentUserId()
            SentryReporting.captureSupabaseError(
                error,
                operation: "leaderboard_public.fetchSingleUser",
                userId: uid
            )
        }
    }

    private static func makeEntry(from row: SupabaseManager.LeaderboardUserRow) -> LeaderboardEntry {
        LeaderboardEntry(
            id: row.id,
            userName: row.display_name ?? "Anonymous",
            userID: row.legacy_user_id,
            totalXP: row.total_xp,
            weeklyXP: row.weekly_xp,
            streak: row.streak,
            levelTitle: row.level_title,
            drugsStudied: row.drugs_studied,
            accountYear: row.student_level
        )
    }
}

struct LeaderboardRowView: View {
    @Environment(\.appTheme) private var theme
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let cyan = Color(hex: "00d4ff")
    private let progress = UserProgressService.shared

    /// In light mode, match `PlayerTitleCardView` (systemBackground). In dark mode, use the same
    /// semantic card surface as the name plate so the row is not pure black with a gray inset.
    private var rowFill: Color {
        if isCurrentUser { return cyan.opacity(0.15) }
        return colorScheme == .dark ? Color.appCardBackground : Color(.systemBackground)
    }

    private var displayedRankTitle: String {
        let trimmed = entry.levelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rank = trimmed.isEmpty ? (isCurrentUser ? progress.currentRankDisplayTitle : "Unranked") : trimmed
        if let raw = entry.accountYear,
           !raw.isEmpty,
           raw.lowercased() != "other",
           let level = StudentLevel(rawValue: raw) {
            return "\(rank) | \(level.displayLabel)"
        }
        return rank
    }

    var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(rank <= 3 ? rankColor.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 40, height: 40)
                Text("\(rank)")
                    .font(theme.appFont(15, weight: .bold))
                    .foregroundStyle(rank <= 3 ? rankColor : .secondary)
            }

            PlayerTitleCardView(displayName: entry.userName, rankTitle: displayedRankTitle, compact: true)

            Text("\(entry.weeklyXP) XP")
                .font(theme.appFont(15, weight: .bold))
                .foregroundStyle(isCurrentUser ? Color(hex: "00d4ff") : Color(.label))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(rowFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isCurrentUser ? cyan.opacity(0.6) : Color.gray.opacity(0.2),
                    lineWidth: isCurrentUser ? 1.5 : 0.5
                )
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
