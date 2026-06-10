import SwiftUI

struct OnboardingSummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.appSecondaryText)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(.label))

            Spacer()

            Text(value)
                .font(.system(size: 15))
                .foregroundColor(Color.appSecondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
    }
}
