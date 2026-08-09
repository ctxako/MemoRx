import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class OnboardingViewModel: ObservableObject {
    /// Total onboarding steps, used as the progress-bar denominator across the step views.
    /// Pass 1 placeholder: the bar may be re-segmented in Pass 2 (the challenge becomes
    /// 3 real questions), so the denominator lives in one place to keep that change cheap.
    static let totalSteps = 4

    @Published var step: Int
    @Published var isGoingBack: Bool = false

    // Onboarding challenge (Pass 2) — score handed from the challenge screen
    // (WelcomeChallengeStepView) to the result/gap screen (ResultGapStepView).
    // Written once when the user finishes Q3; read by the result screen.
    @Published var challengeCorrect: Int = 0
    @Published var challengeMisses: [OnboardingMiss] = []

    // Step 1 — Identity
    @Published var name: String
    @Published var selectedLevel: StudentLevel? = nil

    // Step 2 — Goal
    @Published var naplexToggleOn: Bool = false
    @Published var selectedExamDate: Date

    // Step 6 — Reminder
    @Published var reminderTime: Date
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Surfaced as a transient toast when a reminder permission request resolves to denied.
    /// `OnboardingShell` renders this; cleared automatically after a few seconds.
    @Published var permissionToast: String?

    private let defaults = UserDefaults.standard

    init() {
        self.step = 1
        let defaults = UserDefaults.standard

        let savedName = defaults.string(forKey: "userName") ?? ""
        if savedName.isEmpty {
            let appleName = defaults.string(forKey: "appleGivenName") ?? ""
            if !appleName.isEmpty {
                name = appleName
            } else {
                let randomNum = Int.random(in: 1...9999)
                name = "PharmStudent\(String(format: "%04d", randomNum))"
            }
        } else {
            name = savedName
        }

        if let raw = defaults.string(forKey: "studentLevel"),
           let level = StudentLevel(rawValue: raw) {
            selectedLevel = level
        }

        let defaultExamDate = Calendar.current.date(
            byAdding: .month, value: 6, to: Date()
        ) ?? Date()
        if let saved = defaults.object(forKey: "naplexDate") as? Double {
            naplexToggleOn = true
            selectedExamDate = Date(timeIntervalSince1970: saved)
        } else {
            selectedExamDate = defaultExamDate
        }

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        if defaults.object(forKey: "dailyReminderHour") != nil {
            comps.hour = defaults.integer(forKey: "dailyReminderHour")
            comps.minute = defaults.integer(forKey: "dailyReminderMinute")
        } else {
            comps.hour = 9
            comps.minute = 0
        }
        reminderTime = Calendar.current.date(from: comps) ?? Date()
    }

    var nameTrimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nameIsValid: Bool {
        let s = nameTrimmed
        guard (2...20).contains(s.count) else { return false }
        guard s.range(of: "^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$",
                      options: .regularExpression) != nil else { return false }
        return !s.contains("  ")
    }

    /// True when the user authenticated via Sign in with Apple on this device.
    /// Used by IdentityStepView to hide the name field (Apple already provided it).
    var signedInWithApple: Bool {
        !(defaults.string(forKey: "appleGivenName") ?? "").isEmpty
    }

    var savedNaplexDate: Date? {
        guard let ts = defaults.object(forKey: "naplexDate") as? Double else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    func advance() {
        let previousStep = step
        isGoingBack = false
        withAnimation(.easeInOut(duration: 0.28)) {
            step += 1
        }
        SentryReporting.breadcrumb(
            category: "onboarding",
            message: "step.advance",
            data: ["from": previousStep, "to": step]
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func goBack() {
        guard step > 1 else { return }
        let previousStep = step
        isGoingBack = true
        withAnimation(.easeInOut(duration: 0.28)) {
            step -= 1
        }
        SentryReporting.breadcrumb(
            category: "onboarding",
            message: "step.back",
            data: ["from": previousStep, "to": step]
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func commitIdentity() {
        defaults.set(nameTrimmed, forKey: "userName")
        defaults.set(selectedLevel?.rawValue ?? "", forKey: "studentLevel")
        defaults.set(selectedLevel?.title ?? "", forKey: "studentLevelTitle")
        if defaults.object(forKey: "startDate") == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: "startDate")
        }
        UserProgressService.shared.syncProfileOnly()
        syncDisplayNameToSupabase(nameTrimmed)
    }

    private func syncDisplayNameToSupabase(_ name: String) {
        Task {
            var currentName = name
            for attempt in 0..<3 {
                do {
                    try await SupabaseManager.changeDisplayName(currentName)
                    return
                } catch SupabaseManager.ChangeDisplayNameError.taken {
                    let fresh = Int.random(in: 1...9999)
                    currentName = "PharmStudent\(String(format: "%04d", fresh))"
                    self.name = currentName
                    defaults.set(currentName, forKey: "userName")
                } catch {
                    #if DEBUG
                    print("syncDisplayNameToSupabase attempt \(attempt + 1)/3: \(error)")
                    #endif
                    return
                }
            }
        }
    }

    /// Marks `has_completed_onboarding = true` on the server. Called from `ReadyStepView`'s
    /// finish action, not from any mid-flow commit, so a user who quits before "Let's go!"
    /// re-enters onboarding on next launch.
    func commitOnboardingFinished() {
        UserProgressService.shared.setOnboardingCompleted()
    }

    func commitNaplex() {
        if naplexToggleOn {
            defaults.set(selectedExamDate.timeIntervalSince1970, forKey: "naplexDate")
        } else {
            defaults.removeObject(forKey: "naplexDate")
        }
    }

    func commitReminder() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        defaults.set(comps.hour ?? 9, forKey: "dailyReminderHour")
        defaults.set(comps.minute ?? 0, forKey: "dailyReminderMinute")

        if notificationStatus == .authorized || notificationStatus == .provisional {
            defaults.set(true, forKey: "dailyReminderEnabled")
        } else {
            defaults.set(false, forKey: "dailyReminderEnabled")
        }

        NotificationManager.shared.refreshDailyReminderIfAuthorized()
        UserProgressService.shared.syncProfileOnly()
    }

    /// Requests notification permission. If the user denies (now or previously),
    /// surfaces a toast so they are not silently dropped onto the next step thinking
    /// reminders are on.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshNotificationStatus()
                if !granted {
                    self.showPermissionDeniedToast()
                }
            }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    /// Public so ReminderStep can also trigger the toast when the user taps Continue
    /// while permission is already `.denied` (no new system prompt fires in that case).
    func showPermissionDeniedToast() {
        permissionToast = "Couldn\u{2019}t enable reminders \u{2014} go to Settings \u{203A} Notifications to turn them on."
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if permissionToast != nil { permissionToast = nil }
        }
    }
}
