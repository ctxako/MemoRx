import SwiftUI
import UIKit

// MARK: - SwiftUI Color tokens

extension Color {
    // Surfaces
    static var appBackground: Color { Color(UIColor.appBackground) }
    static var appCardBackground: Color { Color(UIColor.appCardBackground) }
    static var appElevatedCard: Color { Color(UIColor.appElevatedCard) }
    static var appInputBackground: Color { Color(UIColor.appInputBackground) }

    // Text
    static var appPrimaryText: Color { Color(UIColor.appPrimaryText) }
    static var appSecondaryText: Color { Color(UIColor.appSecondaryText) }
    static var appTertiaryText: Color { Color(UIColor.appTertiaryText) }
}

extension Font {
    /// Body / supporting text. Returns SF Pro by default.
    /// Theme-aware serif variant is provided by `AppTheme.appFont(_:weight:)`.
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Adaptive UIColor definitions

extension UIColor {
    private static var isHighContrastEnabled: Bool {
        UserDefaults.standard.bool(forKey: "highContrastEnabled")
    }

    /// Root screen background: soft gray (light) / system dark base (dark).
    static var appBackground: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0x000000) : UIColor(rgb: 0xFFFFFF)
            }
            return darkMode ? UIColor(rgb: 0x1C1C1E) : UIColor(rgb: 0xEBEBED)
        }
    }
    // #333435 dark / system light
    static var appCardBackground: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0x141416) : UIColor(rgb: 0xF4F5F8)
            }
            return darkMode ? UIColor(rgb: 0x333435) : UIColor(rgb: 0xFAFBFF)
        }
    }
    // #3D3E3F dark / system light
    static var appElevatedCard: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0x1D1E20) : UIColor(rgb: 0xECEEF3)
            }
            return darkMode ? UIColor(rgb: 0x3D3E3F) : .tertiarySystemGroupedBackground
        }
    }
    // #484A4B dark / system light  (inputs, badges, pills)
    static var appInputBackground: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0x25272A) : UIColor(rgb: 0xE3E5EB)
            }
            return darkMode ? UIColor(rgb: 0x484A4B) : .secondarySystemFill
        }
    }
    // #F5F5F5 dark / label light
    static var appPrimaryText: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0xFFFFFF) : UIColor(rgb: 0x111111)
            }
            return darkMode ? UIColor(rgb: 0xF5F5F5) : .label
        }
    }
    // #A0A1A2 dark / secondaryLabel light
    static var appSecondaryText: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0xC7C8CC) : UIColor(rgb: 0x424242)
            }
            return darkMode ? UIColor(rgb: 0xA0A1A2) : .secondaryLabel
        }
    }
    // #636466 dark / tertiaryLabel light
    static var appTertiaryText: UIColor {
        UIColor { tc in
            let darkMode = tc.userInterfaceStyle == .dark
            if isHighContrastEnabled {
                return darkMode ? UIColor(rgb: 0x93959D) : UIColor(rgb: 0x5D6168)
            }
            return darkMode ? UIColor(rgb: 0x636466) : .tertiaryLabel
        }
    }

    private convenience init(rgb hex: Int) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: 1
        )
    }
}
