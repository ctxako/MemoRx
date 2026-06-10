import SwiftUI

struct PlayerTitleCardView: View {
    let displayName: String
    let rankTitle: String
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var cardFill: Color {
        colorScheme == .dark ? Color.appCardBackground : Color(.systemBackground)
    }

    private var nameFontSize: CGFloat { compact ? 19 : 20 }
    private var rankFontSize: CGFloat { compact ? 13 : 14 }
    private var hPadding: CGFloat { compact ? 14 : 16 }
    private var vPadding: CGFloat { compact ? 8 : 14 }

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(displayName)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .kerning(2.0)
                .foregroundStyle(Color(.label))
            Text(rankTitle)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .textCase(.uppercase)
                .kerning(1.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.gray.opacity(0.2),
                    lineWidth: 0.5
                )
        }
    }
}
