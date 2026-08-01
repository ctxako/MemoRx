import SwiftUI
import UserNotifications
import StoreKit

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("userName") private var userName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = true
    @AppStorage("highContrastEnabled") private var highContrastEnabled = false
    @AppStorage("selectedTheme") private var selectedThemeRaw = AppTheme.standard.rawValue
    @AppStorage("studentLevel") private var studentLevel = ""
    @AppStorage("hasSeenAuth") private var hasSeenAuth = true
    @AppStorage("appleUserID") private var appleUserID = ""
    @StateObject private var progress = UserProgressService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showSignOutAlert = false
    @State private var showResetAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showManageSubscriptions = false
    @State private var showPaywall = false
    @State private var showChangeUsernameSheet = false
    @ObservedObject private var subscriptions = SubscriptionManager.shared

    private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

    private var subscriptionStatusText: String {
        subscriptions.subscriptionStatusLabel.isEmpty ? "No active plan" : subscriptions.subscriptionStatusLabel
    }

    private var subscriptionStatusColor: Color {
        let label = subscriptions.subscriptionStatusLabel
        if label.isEmpty { return Color.appSecondaryText }
        if label == "Lifetime" { return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255) }
        if label.contains("Trial") { return .blue }
        return .green
    }
    @State private var reminderTime: Date = {
        let hour = UserDefaults.standard.object(forKey: "dailyReminderHour") != nil
            ? UserDefaults.standard.integer(forKey: "dailyReminderHour") : 9
        let minute = UserDefaults.standard.object(forKey: "dailyReminderMinute") != nil
            ? UserDefaults.standard.integer(forKey: "dailyReminderMinute") : 0
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }()

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private var naplexDateBinding: Binding<Date> {
        Binding(
            get: {
                guard let ts = UserDefaults.standard.object(forKey: "naplexDate") as? Double else {
                    return Date()
                }
                return Date(timeIntervalSince1970: ts)
            },
            set: { newDate in
                UserDefaults.standard.set(newDate.timeIntervalSince1970, forKey: "naplexDate")
                UserProgressService.shared.syncProfileOnly()
            }
        )
    }

    private var highContrastBinding: Binding<Bool> {
        Binding(
            get: { highContrastEnabled },
            set: { enabled in
                highContrastEnabled = enabled
                UserProgressService.shared.syncProfileOnly()
            }
        )
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    accountSection
                    subscriptionSection
                    naplexSection
                    notificationsSection
                    appearanceSection
                    accessibilitySection
                    aboutSection
                    dangerZoneSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear your local data and return you to the welcome screen.")
        }
        .alert("Reset Progress", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your XP, streaks, and quiz history. This cannot be undone.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, XP, streak, quiz history, and request log will be permanently deleted from our servers. This action cannot be undone.")
        }
        .sheet(isPresented: $showChangeUsernameSheet) {
            ChangeUsernameSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }

    // MARK: — Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Account")
            VStack(spacing: 0) {
                Button {
                    showChangeUsernameSheet = true
                } label: {
                    HStack {
                        Text("Display Name")
                            .font(theme.appFont(16))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(userName.capitalized)
                            .font(theme.appFont(15))
                            .foregroundStyle(.secondary)
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTertiaryText)
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
                HStack {
                    Text("Year")
                        .font(theme.appFont(16))
                    Spacer()
                    Picker("", selection: Binding<String>(
                        get: { studentLevel },
                        set: { newVal in
                            studentLevel = newVal
                            let level = StudentLevel(rawValue: newVal)
                            UserDefaults.standard.set(level?.title ?? "", forKey: "studentLevelTitle")
                            UserProgressService.shared.syncProfileOnly()
                        }
                    )) {
                        Text("—").tag("")
                        ForEach(StudentLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayLabel).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                Divider().padding(.leading, 16)
                settingsRow(label: "User ID", value: "@\(progress.userID)")
                if appleUserID.isEmpty {
                    Divider().padding(.leading, 16)
                    Button {
                        hasSeenAuth = false
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sign in with Apple")
                                .font(theme.appFont(16, weight: .semibold))
                                .foregroundStyle(Color(.label))
                            Text("Sync your progress across devices.")
                                .font(theme.appFont(13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.leading, 16)
                Button {
                    showSignOutAlert = true
                } label: {
                    HStack {
                        Text("Sign Out")
                            .font(theme.appFont(16))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var naplexSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("NAPLEX")
            VStack(spacing: 0) {
                HStack {
                    DatePicker("Exam Date", selection: naplexDateBinding, displayedComponents: .date)
                        .font(theme.appFont(16))
                        .datePickerStyle(.compact)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Notifications")
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Reminder")
                            .font(theme.appFont(16))
                        Text("We will ask permission when you enable this.")
                            .font(theme.appFont(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { dailyReminderEnabled },
                            set: { enabled in
                                if enabled {
                                    let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                                    UserDefaults.standard.set(comps.hour ?? 9, forKey: "dailyReminderHour")
                                    UserDefaults.standard.set(comps.minute ?? 0, forKey: "dailyReminderMinute")
                                    NotificationManager.shared.enableDailyReminder { granted in
                                        DispatchQueue.main.async {
                                            dailyReminderEnabled = granted
                                            UserProgressService.shared.syncProfileOnly()
                                        }
                                    }
                                } else {
                                    dailyReminderEnabled = false
                                    NotificationManager.shared.cancelDailyReminder()
                                    UserProgressService.shared.syncProfileOnly()
                                }
                            }
                        )) {
                            EmptyView()
                        }
                        .accessibilityLabel("Daily reminder")
                        .accessibilityHint("Enables a once-daily study reminder notification")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if dailyReminderEnabled {
                    Divider()
                    HStack {
                        Text("Reminder Time")
                            .font(.system(size: 15))
                        Spacer()
                        DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: reminderTime) { _, newVal in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                                NotificationManager.shared.updateReminderTime(
                                    hour: comps.hour ?? 9,
                                    minute: comps.minute ?? 0
                                )
                                UserProgressService.shared.syncProfileOnly()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Accessibility")
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Increased Contrast")
                            .font(theme.appFont(16))
                        Text("Deeper blacks in dark mode and stronger light-mode contrast. Applies instantly, no restart needed.")
                            .font(theme.appFont(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Increased Contrast", isOn: highContrastBinding)
                        .labelsHidden()
                        .accessibilityLabel("Increased contrast")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Danger Zone")
            VStack(spacing: 8) {
                Button {
                    showResetAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                        Text("Reset Progress")
                            .font(theme.appFont(16))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    deleteAccountError = nil
                    showDeleteAccountAlert = true
                } label: {
                    HStack(spacing: 12) {
                        if isDeletingAccount {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.red)
                                .frame(width: 15, height: 15)
                        } else {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 15))
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDeletingAccount ? "Deleting account\u{2026}" : "Delete Account")
                                .font(theme.appFont(16))
                                .foregroundStyle(.red)
                            Text("Permanently removes your account and all data.")
                                .font(theme.appFont(12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .disabled(isDeletingAccount)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let err = deleteAccountError {
                    Text(err)
                        .font(theme.appFont(12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        }
    }


    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("About & legal")
            VStack(spacing: 0) {
                Button {
                    if let url = URL(string: "mailto:support@memorx.app") {
                        openURL(url)
                    }
                } label: {
                    settingsLegalRow(symbol: "envelope.fill", title: "Contact / Feedback")
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                Divider().padding(.leading, 16)
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    settingsLegalRow(symbol: "hand.raised.fill", title: "Privacy Policy")
                }
                Divider().padding(.leading, 16)
                NavigationLink {
                    SourcesView()
                } label: {
                    settingsLegalRow(symbol: "books.vertical.fill", title: "Sources")
                }
                Divider().padding(.leading, 16)
                NavigationLink {
                    TermsOfUseView()
                } label: {
                    settingsLegalRow(symbol: "doc.text.fill", title: "Terms of Use")
                }
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 8) {
                Image("AboutAppMark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("MemoRx")
                    .font(theme.appFont(20, weight: .bold))

                Text("Version \(appVersion)")
                    .font(theme.appFont(13))
                    .foregroundStyle(.secondary)

                Text("© 2026 MemoRx. All rights reserved.")
                    .font(theme.appFont(13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func settingsLegalRow(symbol: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(theme.appFont(16))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.appTertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }


    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRaw) ?? .premium
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Appearance")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        let locked = theme.requiresSubscription && !subscriptions.hasActiveSubscription
                        Button {
                            if locked {
                                showPaywall = true
                            } else {
                                selectedThemeRaw = theme.rawValue
                                UserProgressService.shared.syncProfileOnly()
                            }
                        } label: {
                            ThemePreviewCard(
                                theme: theme,
                                isSelected: selectedTheme == theme,
                                isLocked: locked
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: — Subscription section

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Subscription")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(subscriptionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(subscriptionStatusText)
                        .font(theme.appFont(16, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 16)

                if subscriptions.hasActiveSubscription {
                    Button {
                        showManageSubscriptions = true
                    } label: {
                        HStack {
                            Text("Manage Subscription")
                                .font(theme.appFont(16))
                                .foregroundStyle(Color(.label))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Text("View Plans")
                                .font(theme.appFont(16, weight: .semibold))
                                .foregroundStyle(warmGold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(warmGold.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: — Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(theme.appFont(12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(theme.appFont(16))
            Spacer()
            Text(value)
                .font(theme.appFont(15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: — Actions

    private func resetProgress() {
        let defaults = UserDefaults.standard
        let prefixes = ["quizXPAwarded_", "dailyQuizXPAwarded_", "streakMilestoneAwarded_", "classCompletionAwarded_"]
        for key in defaults.dictionaryRepresentation().keys {
            if prefixes.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(false, forKey: "pendingSyncNeeded")
        progress.totalXP = 0
        progress.weeklyXP = 0
        progress.streak = 0
        progress.lastStudyDateString = ""
        progress.drugScores = [:]
        progress.drugDifficultyRatings = [:]
        progress.drugNextReview = [:]
        progress.save()
        progress.syncProfileOnly()

        Task {
            await SupabaseManager.ensureAnonymousSession()
            guard await SupabaseManager.currentUserId() != nil else { return }
            do {
                // Single SECURITY DEFINER RPC: wipes drug_progress, quiz_attempts,
                // daily_completions, user_milestone_claims, and zeros XP/streak.
                try await SupabaseManager.resetMyProgress()
            } catch {
                #if DEBUG
            print("Supabase reset_my_progress failed: \(error)")
            #endif
            }
        }
        dismiss()
    }

    private func signOut() {
        let defaults = UserDefaults.standard
        let priorLegacyUserID = defaults.string(forKey: "userID") ?? progress.userID
        // Reuse reset semantics so a signed-out account does not keep prior XP/quiz data.
        let prefixes = ["quizXPAwarded_", "dailyQuizXPAwarded_", "streakMilestoneAwarded_", "classCompletionAwarded_"]
        for key in defaults.dictionaryRepresentation().keys {
            if prefixes.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(false, forKey: "pendingSyncNeeded")
        progress.totalXP = 0
        progress.weeklyXP = 0
        progress.streak = 0
        progress.lastStudyDateString = ""
        progress.drugScores = [:]
        progress.drugScoreSources = [:]
        progress.drugDifficultyRatings = [:]
        progress.drugNextReview = [:]
        progress.flaggedDrugIds = []
        progress.classQuizHistory = []
        progress.save()

        // Non-destructive sign-out: end the Supabase session only. Server-side data
        // (users row, drug_progress, quiz_attempts, daily_completions) is preserved so
        // signing back in with the same Apple ID restores progress via hydrateFromServerIfNeeded.
        _ = priorLegacyUserID
        Task {
            await SupabaseManager.signOutCurrentSession()
        }

        SubscriptionManager.shared.reset()
        defaults.removeObject(forKey: "hasSeenAuth")
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "appleUserID")
        defaults.removeObject(forKey: "freeQuizCountByDay")
        defaults.removeObject(forKey: "appleGivenName")
        defaults.removeObject(forKey: "isLifetime")
        defaults.removeObject(forKey: "userName")
        defaults.removeObject(forKey: "studentLevel")
        defaults.removeObject(forKey: "studentLevelTitle")
        defaults.removeObject(forKey: "startDate")
        defaults.removeObject(forKey: "naplexDate")
        defaults.removeObject(forKey: "userID")
        defaults.removeObject(forKey: "dailyDrugSequenceAnchorDate")
        hasCompletedOnboarding = false
        dismiss()
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteAccountError = nil

        Task {
            do {
                await SupabaseManager.ensureAnonymousSession()
                guard await SupabaseManager.currentUserId() != nil else {
                    isDeletingAccount = false
                    deleteAccountError = "Couldn\u{2019}t reach the server. Please check your connection and try again."
                    return
                }
                try await SupabaseManager.deleteMyAccount()
            } catch {
                isDeletingAccount = false
                deleteAccountError = "Couldn\u{2019}t delete your account: \(error.localizedDescription)"
                return
            }

            await SupabaseManager.signOutCurrentSession()

            await MainActor.run {
                let defaults = UserDefaults.standard
                for key in defaults.dictionaryRepresentation().keys {
                    if key.hasPrefix("quizXPAwarded_") ||
                       key.hasPrefix("dailyQuizXPAwarded_") ||
                       key.hasPrefix("streakMilestoneAwarded_") ||
                       key.hasPrefix("classCompletionAwarded_") {
                        defaults.removeObject(forKey: key)
                    }
                }
                progress.totalXP = 0
                progress.weeklyXP = 0
                progress.streak = 0
                progress.lastStudyDateString = ""
                progress.drugScores = [:]
                progress.drugScoreSources = [:]
                progress.drugDifficultyRatings = [:]
                progress.drugNextReview = [:]
                progress.flaggedDrugIds = []
                progress.classQuizHistory = []
                progress.save()

                let purge = [
                    "hasSeenAuth", "hasCompletedOnboarding", "appleUserID",
                    "appleGivenName", "isLifetime", "userName", "studentLevel",
                    "studentLevelTitle", "startDate", "naplexDate", "userID",
                    "freeQuizCountByDay", "dailyDrugSequenceAnchorDate",
                    "dailyReminderEnabled", "dailyReminderHour", "dailyReminderMinute",
                    "selectedTheme", "highContrastEnabled"
                ]
                for k in purge { defaults.removeObject(forKey: k) }

                SubscriptionManager.shared.reset()
                hasCompletedOnboarding = false
                isDeletingAccount = false
                dismiss()
            }
        }
    }
}


// MARK: - Change Username Sheet

private enum NameAvailability: Equatable {
    case unknown, checking, available, taken
}

struct ChangeUsernameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var currentName = ""
    @Environment(\.appTheme) private var theme

    @State private var fieldText = ""
    @State private var availability: NameAvailability = .unknown
    @State private var availabilityTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var cooldownUntil: Date?
    @State private var isLoadingCooldown = true
    @FocusState private var fieldFocused: Bool

    private var nameTrimmed: String {
        fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameHasValidFormat: Bool {
        let s = nameTrimmed
        guard (2...20).contains(s.count) else { return false }
        guard s.range(of: "^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$", options: .regularExpression) != nil else { return false }
        return !s.contains("  ")
    }

    private var inlineHint: String? {
        if fieldText.isEmpty { return nil }
        let t = nameTrimmed
        if t.count < 2 { return "At least 2 characters" }
        if fieldText.contains("  ") { return "Only one space at a time" }
        if t.count > 20 { return "20 characters max" }
        switch availability {
        case .checking: return "Checking\u{2026}"
        case .taken:    return "Username taken"
        case .available: return "Available"
        case .unknown:  return nil
        }
    }

    private var hintColor: Color {
        switch availability {
        case .available: return .green
        case .taken:     return .red
        default:
            if !nameTrimmed.isEmpty && !nameHasValidFormat { return .red }
            return .secondary
        }
    }

    private var canSave: Bool {
        nameHasValidFormat && availability == .available && !isSaving
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoadingCooldown {
                    ProgressView()
                } else if let until = cooldownUntil {
                    lockedView(until: until)
                } else {
                    editView
                }
            }
            .navigationTitle("Change Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if cooldownUntil == nil && !isLoadingCooldown {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Save") { Task { await save() } }
                                .disabled(!canSave)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .task { await loadCooldown() }
    }

    private var editView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .trailing) {
                        TextField("Username", text: $fieldText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .focused($fieldFocused)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.trailing, 44)
                            .frame(minHeight: 52)
                            .background(Color.appCardBackground)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(fieldBorderColor, lineWidth: 1.5)
                            )
                            .onChange(of: fieldText) { _, newVal in
                                let filtered = newVal.unicodeScalars.filter { s in
                                    (s.value >= 65 && s.value <= 90) ||
                                    (s.value >= 97 && s.value <= 122) ||
                                    (s.value >= 48 && s.value <= 57) ||
                                    s.value == 32
                                }.reduce("") { $0 + String($1) }
                                var next = filtered
                                if next.count > 20 { next = String(next.prefix(20)) }
                                if next != newVal { fieldText = next; return }
                                scheduleAvailabilityCheck()
                            }

                        if !fieldText.isEmpty {
                            Group {
                                switch availability {
                                case .checking:
                                    ProgressView().scaleEffect(0.75)
                                case .available:
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                case .taken:
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                case .unknown:
                                    if !nameHasValidFormat {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.appSecondaryText.opacity(0.45))
                                    }
                                }
                            }
                            .padding(.trailing, 14)
                        }
                    }

                    HStack {
                        if let hint = inlineHint {
                            Text(hint)
                                .font(.system(size: 12))
                                .foregroundStyle(hintColor)
                                .animation(.none, value: hint)
                        }
                        Spacer()
                        Text("\(nameTrimmed.count)/20")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                nameTrimmed.count > 17
                                    ? .orange
                                    : Color.appSecondaryText.opacity(0.5)
                            )
                    }
                    .padding(.horizontal, 4)
                }

                if let err = saveError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules")
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .foregroundStyle(.secondary)
                    Text("\u{2022} 2\u{2013}20 characters")
                    Text("\u{2022} Letters, numbers, spaces only")
                    Text("\u{2022} No consecutive spaces")
                    Text("\u{2022} Must be unique")
                    Text("\u{2022} One change every 30 days")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = false }
        .onAppear { fieldFocused = true }
    }

    private func lockedView(until date: Date) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Username locked")
                .font(.system(size: 20, weight: .semibold))
            Text("You can change your username again on\n\(date.formatted(date: .long, time: .omitted)).")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var fieldBorderColor: Color {
        switch availability {
        case .available: return .green.opacity(0.55)
        case .taken:     return .red.opacity(0.5)
        default:
            if !fieldText.isEmpty && !nameHasValidFormat { return .red.opacity(0.4) }
            return Color.appSecondaryText.opacity(0.18)
        }
    }

    private func scheduleAvailabilityCheck() {
        availabilityTask?.cancel()
        availability = .unknown
        guard nameHasValidFormat else { return }
        if nameTrimmed.lowercased() == currentName.lowercased() {
            availability = .available
            return
        }
        availability = .checking
        availabilityTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let isAvail = (try? await SupabaseManager.isDisplayNameAvailable(nameTrimmed)) ?? true
            availability = isAvail ? .available : .taken
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        saveError = nil
        do {
            try await UserProgressService.shared.updateDisplayName(nameTrimmed)
            dismiss()
        } catch UserProgressService.DisplayNameError.taken {
            availability = .taken
            saveError = "That username was just taken. Try another."
        } catch UserProgressService.DisplayNameError.invalidFormat {
            saveError = "Username doesn\u{2019}t meet the format rules."
        } catch UserProgressService.DisplayNameError.tooSoon(let unlockDate) {
            cooldownUntil = unlockDate
        } catch UserProgressService.DisplayNameError.notAuthenticated {
            saveError = "Session expired. Please restart the app and try again."
        } catch {
            saveError = "Couldn\u{2019}t save. Please try again."
        }
        isSaving = false
    }

    private func loadCooldown() async {
        defer { isLoadingCooldown = false }
        guard let uid = await SupabaseManager.currentUserId() else {
            fieldText = currentName
            return
        }
        if let updatedAt = try? await SupabaseManager.fetchDisplayNameUpdatedAt(userId: uid) {
            let unlockDate = updatedAt.addingTimeInterval(30 * 24 * 60 * 60)
            if unlockDate > Date() {
                cooldownUntil = unlockDate
                return
            }
        }
        fieldText = currentName
    }
}
