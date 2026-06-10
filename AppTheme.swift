import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case premium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .premium: return "Premium"
        }
    }

    var accentColor: Color {
        switch self {
        case .premium: return Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
        }
    }

    var cardSurface: Color {
        switch self {
        case .premium: return Color(red: 51 / 255, green: 52 / 255, blue: 53 / 255)
        }
    }

    var sectionSurface: Color {
        switch self {
        case .premium: return Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
        }
    }
}

struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            miniCard
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.accentColor)
                            .background(Circle().fill(Color.black.opacity(0.5)).padding(2))
                            .padding(8)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.accentColor, lineWidth: 2)
                    }
                }

            Text(theme.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? theme.accentColor : Color.white.opacity(0.65))
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

            Text("Diazepam")
                .font(.system(size: 20, weight: .semibold, design: .serif))
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
                    .fill(theme.accentColor.opacity(0.7))
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("WHY IT MATTERS")
                        .font(.system(size: 7, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(theme.accentColor)

                    Text("Schedule IV")
                        .font(.system(size: 9, weight: .medium))
                        .italic()
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(theme.accentColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.accentColor.opacity(0.20), lineWidth: 0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 148, height: 188)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
