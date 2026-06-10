import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case standard
    case premium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .premium:  return "Premium"
        }
    }

    // Selection indicator / checkmark color in the Settings picker
    var accentColor: Color {
        switch self {
        case .standard: return Color(white: 0.52)
        case .premium:  return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
        }
    }

    // Front face card background
    var cardFrontSurface: Color {
        switch self {
        case .standard: return Color(red: 51 / 255, green: 52 / 255, blue: 53 / 255)  // #333435
        case .premium:  return Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)  // #1A1A1C — matches section cards
        }
    }

    // Section card background (MOA, Indications, Dosage, etc.)
    var sectionSurface: Color {
        switch self {
        case .standard: return Color(red: 51 / 255, green: 52 / 255, blue: 53 / 255)  // #333435
        case .premium:  return Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)  // #1A1A1C
        }
    }

    // WHY IT MATTERS label, bar, fill tint, stroke
    var whyItMattersAccent: Color {
        switch self {
        case .standard: return Color(red: 243 / 255, green: 207 / 255, blue: 74 / 255)  // warm yellow
        case .premium:  return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255) // warm gold
        }
    }

    // Quiz Me button border
    var quizButtonBorder: Color {
        switch self {
        case .standard: return Color.white
        case .premium:  return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
        }
    }

    // Indications bullet icon color
    var indicationAccent: Color {
        switch self {
        case .standard: return Color.white.opacity(0.45)  // same as other bullets — no accent
        case .premium:  return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.50)
        }
    }

    // Drug hero name font (front + back header)
    var usesSerifHero: Bool {
        switch self {
        case .standard: return false  // serif via .app()
        case .premium:  return true   // SF Pro Serif
        }
    }

    var requiresSubscription: Bool {
        switch self {
        case .standard: return false
        case .premium:  return true
        }
    }
}

// MARK: - Theme-aware fonts

extension AppTheme {
    private var bodyDesign: Font.Design {
        self == .premium ? .serif : .default
    }

    /// Body / supporting text font — SF Pro on standard, SF Serif (New York) on premium.
    func appFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: bodyDesign)
    }

    /// Drug hero name (34–38pt semibold). Premium swaps to serif via .appFont path elsewhere.
    var uiHero: Font {
        .system(size: 36, weight: .semibold, design: self == .premium ? .serif : .rounded)
    }

    /// Screen / section titles — 17pt semibold.
    var uiTitle: Font {
        .system(size: 17, weight: .semibold, design: bodyDesign)
    }

    /// Supporting lines (brand names, etc.) — 16pt regular.
    var uiBody: Font {
        .system(size: 16, weight: .regular, design: bodyDesign)
    }

    /// Hints, tertiary copy — 13pt regular.
    var uiSubtle: Font {
        .system(size: 13, weight: .regular, design: bodyDesign)
    }

    /// Uppercase collection / tag pills — 11pt medium.
    var uiLabel: Font {
        .system(size: 11, weight: .medium, design: bodyDesign)
    }
}

// MARK: - SwiftUI Environment

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .standard
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    var isLocked: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            miniCard
                .overlay(alignment: .topTrailing) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .padding(8)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.accentColor)
                            .background(Circle().fill(Color.black.opacity(0.5)).padding(2))
                            .padding(8)
                    }
                }
                .overlay {
                    if isSelected && !isLocked {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.accentColor, lineWidth: 2)
                    }
                }
                .opacity(isLocked ? 0.55 : 1)

            Text(theme.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected && !isLocked ? theme.accentColor : Color.white.opacity(0.65))
        }
    }

    private var miniCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BENZODIAZEPINE")
                .font(.system(size: 7, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.82))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())

            Group {
                if theme.usesSerifHero {
                    Text("Diazepam")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                } else {
                    Text("Diazepam")
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.top, 10)

            Text("Valium / Diastat")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.top, 3)

            Divider()
                .opacity(0.5)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .fill(theme.whyItMattersAccent.opacity(0.7))
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("WHY IT MATTERS")
                        .font(.system(size: 7, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(theme.whyItMattersAccent)

                    Text("Schedule IV")
                        .font(.system(size: 9, weight: .medium))
                        .italic()
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(theme.whyItMattersAccent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.whyItMattersAccent.opacity(0.20), lineWidth: 0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 148, height: 188)
        .background(theme.cardFrontSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
