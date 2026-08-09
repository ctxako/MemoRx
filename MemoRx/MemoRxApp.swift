//
//  MemoRxApp.swift
//  MemoRx
//
//  Created by Charles Thomas Xavier Austin III on 3/30/26.
//

import SwiftUI

@main
struct MemoRxApp: App {
    @AppStorage("selectedTheme") private var selectedThemeRaw = AppTheme.standard.rawValue

    init() {
        // Sentry must initialize before every other side-effect so startup crashes,
        // notification-permission failures, and StoreKit configuration are all captured.
        SentryReporting.start()

        // Capture runtime (-marketingCapture, DEBUG only) keeps Sentry but makes
        // no user-scoped Supabase writes: no notification refresh, no
        // subscription sync (see MarketingCaptureRuntime).
        guard !MarketingCaptureRuntime.isActive else { return }

        NotificationManager.shared.refreshDailyReminderIfAuthorized()
        Task {
            await SubscriptionManager.shared.configureOnLaunch()
        }
    }

    private var theme: AppTheme {
        AppTheme(rawValue: selectedThemeRaw) ?? .standard
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if MarketingCaptureRuntime.isActive {
                    MarketingCaptureRootView()
                } else {
                    ContentView()
                }
            }
            .environment(\.appTheme, theme)
            .preferredColorScheme(.dark)
        }
    }
}
