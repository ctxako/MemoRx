import Foundation
import Sentry

/// Central Sentry start + reporting helper. Reads `SENTRY_DSN` from Info.plist (injected
/// via `Config/Supabase.xcconfig` → `Config/Supabase.local.xcconfig`). If the DSN is empty
/// or unsubstituted, `start()` logs a warning and no-ops so the app still runs.
///
/// All helpers below are safe to call even when Sentry never started — they short-circuit.
enum SentryReporting {
    /// Set inside `start()` on a successful `SentrySDK.start`; gates every helper so they
    /// no-op (rather than crash or no-op-via-SDK) when the DSN is missing.
    private static var isStarted = false

    /// Idempotent. Call as the very first statement in `MemoRxApp.init()`.
    static func start() {
        guard !isStarted else { return }
        let host = trimmedInfoString("SENTRY_DSN_HOST")
        let project = trimmedInfoString("SENTRY_DSN_PROJECT")
        guard !host.isEmpty, !host.hasPrefix("$("),
              !project.isEmpty, !project.hasPrefix("$(") else {
            print("[Sentry] SENTRY_DSN_HOST/PROJECT missing or unsubstituted — Sentry init skipped.")
            return
        }
        let dsn = "https://" + host + "/" + project
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.environment = Self.environmentName()
            options.tracesSampleRate = 0.2
            options.attachStacktrace = true
            options.enableAutoPerformanceTracing = true
            options.enableAppHangTracking = true
            options.enableUserInteractionTracing = true
            // Health-adjacent app: never auto-send user identifiers (IP, email, username).
            options.sendDefaultPii = false
        }
        isStarted = true
    }

    // MARK: - User identification (anonymous only)

    /// Tag the current Sentry scope with the anonymous Supabase auth UUID — `id` only.
    /// No email / username / display name / Apple ID is ever attached.
    static func setAnonymousUser(_ id: UUID) {
        guard isStarted else { return }
        let user = User()
        user.userId = id.uuidString
        SentrySDK.setUser(user)
    }

    static func clearUser() {
        guard isStarted else { return }
        SentrySDK.setUser(nil)
    }

    // MARK: - Breadcrumbs

    /// Adds a structured breadcrumb. Callers must never pass PII / quiz content / answers in `data`.
    static func breadcrumb(category: String, message: String, data: [String: Any] = [:], level: SentryLevel = .info) {
        guard isStarted else { return }
        let crumb = Breadcrumb()
        crumb.category = category
        crumb.message = message
        crumb.level = level
        if !data.isEmpty { crumb.data = data }
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Error capture

    /// Captures a Supabase-side failure with operation/user tags so events group cleanly per call site.
    /// Pass the anonymous Supabase user UUID (NOT email/name) for correlation.
    static func captureSupabaseError(_ error: Error, operation: String, userId: UUID?, extra: [String: Any] = [:]) {
        guard isStarted else { return }
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "supabase", key: "subsystem")
            scope.setTag(value: operation, key: "operation")
            if let uid = userId {
                scope.setExtra(value: uid.uuidString, key: "user_id")
            }
            for (k, v) in extra { scope.setExtra(value: v, key: k) }
        }
    }

    // MARK: - Helpers

    private static func trimmedInfoString(_ key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func environmentName() -> String {
        #if DEBUG
        return "debug"
        #else
        if isTestFlight() {
            return "testflight"
        }
        return "production"
        #endif
    }

    private static func isTestFlight() -> Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
