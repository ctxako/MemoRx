import Foundation

enum AppRuntimeConfig {
    /// When enabled, the app always tries Supabase first on launch.
    /// If the network fails or the cloud payload is empty, it falls back to the last cached copy,
    /// then to bundled JSON (`drugs.json`, `class_quizzes.json`) so the app stays usable offline.
    static let cloudContentOnly = true
}
