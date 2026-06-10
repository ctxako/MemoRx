import SwiftUI
import UIKit

/// One place for the user-facing support email + a fallback for users without Mail.app
/// configured. `UIApplication.shared.open(url, completionHandler:)` is the only way to
/// distinguish "iOS handed it off" from "no handler" — without the completion handler,
/// tapping the feedback button on a Gmail-only iPhone silently no-ops (audit P1 #8).
enum SupportContact {
    static let email = "hello@ctxa.ltd"

    /// Attempts a `mailto:` open. If iOS reports the URL could not be opened (no Mail app
    /// configured for the system mail handler), copies the address to the clipboard and
    /// invokes `fallback("hello@ctxa.ltd")` so the caller can surface a toast like
    /// "Mail isn't set up. Email address copied — paste it into Gmail or your browser."
    @MainActor
    static func openFeedbackMail(fallback: @escaping (String) -> Void) {
        guard let url = URL(string: "mailto:\(email)") else {
            fallback(email)
            return
        }
        UIApplication.shared.open(url, options: [:]) { accepted in
            if accepted { return }
            UIPasteboard.general.string = email
            fallback(email)
        }
    }
}

/// Floating chip that auto-dismisses after a short interval. Used by feedback / Help
/// surfaces to confirm the fallback (email copied to clipboard) without an alert modal.
struct SupportContactToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }
}
