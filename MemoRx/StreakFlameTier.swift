import SwiftUI

// MARK: - Shared streak / flame tier model
//
// Used by Growth ticker watermark, dashboard inline flames, and the Today tab toolbar streak pill.
// Keep tier thresholds in sync with product copy elsewhere.

/// Buckets that drive flame color, glow, and (in the Growth ticker) pulse behavior.
enum StreakFlameTier: String, CaseIterable {
    case dormant       // streak == 0 (see `tierForTodayToolbar` for “no daily yet” nuance)
    case spark         // 1...2
    case ember         // 3...6
    case blaze         // 7...13
    case inferno       // 14...29
    case legendary     // 30+

    static func from(streak: Int) -> StreakFlameTier {
        switch max(streak, 0) {
        case 0: return .dormant
        case 1...2: return .spark
        case 3...6: return .ember
        case 7...13: return .blaze
        case 14...29: return .inferno
        default: return .legendary
        }
    }

    /// Today toolbar: grey dormant when there is no streak and today’s daily XP has not been earned yet;
    /// if the streak is still 0 but today’s daily is done, show a soft spark so the pill isn’t “dead”.
    static func tierForTodayToolbar(streak: Int, hasCompletedDailyQuizToday: Bool) -> StreakFlameTier {
        if streak == 0 && !hasCompletedDailyQuizToday { return .dormant }
        if streak == 0 && hasCompletedDailyQuizToday { return .spark }
        return .from(streak: streak)
    }

    /// Ordinal rank for celebrations and pulse slow-down on the Growth ticker.
    var rank: Int {
        switch self {
        case .dormant: return 0
        case .spark: return 1
        case .ember: return 2
        case .blaze: return 3
        case .inferno: return 4
        case .legendary: return 5
        }
    }

    var style: StreakFlameStyle {
        switch self {
        case .dormant:
            return StreakFlameStyle(
                baseColor: Color.appTertiaryText,
                coreColor: Color.appTertiaryText,
                lightOpacity: 0.10,
                darkOpacity: 0.14,
                glowColor: .clear,
                glowRadius: 0,
                lightGlowOpacity: 0,
                darkGlowOpacity: 0,
                pulseAmount: 0,
                pulsePeriod: 0
            )
        case .spark:
            return StreakFlameStyle(
                baseColor: Color(red: 1.00, green: 0.74, blue: 0.45),
                coreColor: Color(red: 1.00, green: 0.86, blue: 0.55),
                lightOpacity: 0.20,
                darkOpacity: 0.26,
                glowColor: Color(red: 1.00, green: 0.74, blue: 0.45),
                glowRadius: 6,
                lightGlowOpacity: 0.16,
                darkGlowOpacity: 0.22,
                pulseAmount: 0.018,
                pulsePeriod: 2.4
            )
        case .ember:
            return StreakFlameStyle(
                baseColor: .orange,
                coreColor: Color(red: 1.00, green: 0.86, blue: 0.40),
                lightOpacity: 0.30,
                darkOpacity: 0.36,
                glowColor: .orange,
                glowRadius: 9,
                lightGlowOpacity: 0.22,
                darkGlowOpacity: 0.30,
                pulseAmount: 0.026,
                pulsePeriod: 2.2
            )
        case .blaze:
            return StreakFlameStyle(
                baseColor: Color(red: 1.00, green: 0.45, blue: 0.18),
                coreColor: Color(red: 1.00, green: 0.82, blue: 0.32),
                lightOpacity: 0.40,
                darkOpacity: 0.46,
                glowColor: Color(red: 1.00, green: 0.50, blue: 0.20),
                glowRadius: 13,
                lightGlowOpacity: 0.30,
                darkGlowOpacity: 0.38,
                pulseAmount: 0.036,
                pulsePeriod: 1.9
            )
        case .inferno:
            return StreakFlameStyle(
                baseColor: Color(red: 0.98, green: 0.32, blue: 0.18),
                coreColor: Color(red: 1.00, green: 0.78, blue: 0.30),
                lightOpacity: 0.52,
                darkOpacity: 0.58,
                glowColor: Color(red: 1.00, green: 0.36, blue: 0.18),
                glowRadius: 17,
                lightGlowOpacity: 0.38,
                darkGlowOpacity: 0.46,
                pulseAmount: 0.046,
                pulsePeriod: 1.6
            )
        case .legendary:
            return StreakFlameStyle(
                baseColor: Color(red: 0.95, green: 0.22, blue: 0.18),
                coreColor: Color(red: 1.00, green: 0.84, blue: 0.34),
                lightOpacity: 0.66,
                darkOpacity: 0.72,
                glowColor: Color(red: 1.00, green: 0.28, blue: 0.16),
                glowRadius: 22,
                lightGlowOpacity: 0.48,
                darkGlowOpacity: 0.56,
                pulseAmount: 0.060,
                pulsePeriod: 1.4
            )
        }
    }

    /// Small inline `flame.fill` icons (dashboard cards, etc.): solid tint, no glow.
    func inlineColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .dormant:
            return colorScheme == .dark
                ? Color.appSecondaryText.opacity(0.45)
                : Color.appSecondaryText.opacity(0.35)
        default:
            return style.baseColor
        }
    }

    /// Today tab top pill: **static** fill + flame (no pulse). Glow ramps with tier rank.
    func todayToolbarPillStyle(colorScheme: ColorScheme) -> TodayToolbarStreakPillStyle {
        let isDark = colorScheme == .dark
        switch self {
        case .dormant:
            return TodayToolbarStreakPillStyle(
                flame: isDark ? Color.appSecondaryText.opacity(0.65) : Color.appSecondaryText.opacity(0.55),
                pillFill: isDark ? Color.white.opacity(0.10) : Color.appTertiaryText.opacity(0.16),
                label: Color.appPrimaryText,
                glowColor: .clear,
                glowRadius: 0,
                glowOpacity: 0
            )
        case .spark, .ember, .blaze, .inferno, .legendary:
            let s = style
            let accent = s.baseColor
            let rank = CGFloat(self.rank)
            // Pill fill: light wash in light mode, slightly stronger in dark; redder tiers read warmer.
            let fillOpacityLight = 0.12 + Double(rank) * 0.028
            let fillOpacityDark = 0.18 + Double(rank) * 0.034
            let pillFill = accent.opacity(isDark ? fillOpacityDark : fillOpacityLight)
            // Glow: no Timeline pulse — only a soft shadow behind the pill that grows with tier.
            let glowRadius: CGFloat = 4 + rank * 2.5
            let glowOpacity = isDark ? 0.42 + Double(rank) * 0.04 : 0.32 + Double(rank) * 0.045
            return TodayToolbarStreakPillStyle(
                flame: accent,
                pillFill: pillFill,
                label: Color.appPrimaryText,
                glowColor: accent,
                glowRadius: glowRadius,
                glowOpacity: min(glowOpacity, 0.85)
            )
        }
    }
}

struct StreakFlameStyle {
    let baseColor: Color
    let coreColor: Color
    let lightOpacity: Double
    let darkOpacity: Double
    let glowColor: Color
    let glowRadius: CGFloat
    let lightGlowOpacity: Double
    let darkGlowOpacity: Double
    let pulseAmount: CGFloat
    let pulsePeriod: Double

    func opacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? darkOpacity : lightOpacity
    }

    func glowOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? darkGlowOpacity : lightGlowOpacity
    }
}

/// Colors for the Today toolbar streak capsule (no animation).
struct TodayToolbarStreakPillStyle {
    let flame: Color
    let pillFill: Color
    let label: Color
    let glowColor: Color
    let glowRadius: CGFloat
    let glowOpacity: Double
}
