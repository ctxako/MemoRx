import Foundation

/// Debug-only capture runtime, enabled via the `-marketingCapture` launch argument.
///
/// When active, the app must make **no user-scoped Supabase writes**: no anonymous
/// sign-in (which auto-creates a `public.users` row via `handle_new_auth_user`),
/// no subscription sync, no progress/onboarding queue flush, no daily completion,
/// and no quiz-attempt writes. Every suppression point checks this flag — never
/// Simulator hygiene.
enum MarketingCaptureRuntime {
    static let isActive: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-marketingCapture")
        #else
        return false
        #endif
    }()
}
