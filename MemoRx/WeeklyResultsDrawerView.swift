import SwiftUI

/// Drawer-style sheet that lists the signed-in user's past weekly placements.
/// Presented from the Growth/Dashboard. Top emphasizes the most recent week with
/// rank-aware copy (#1/#2/#3 medal, others neutral). Below: a tight list of the rest.
struct WeeklyResultsDrawerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = WeeklyResultsService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(String(localized: "Weekly Results"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .task { await service.load() }
    }

    @ViewBuilder
    private var content: some View {
        if service.isLoading && service.rows.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "Loading…"))
                    .font(theme.appFont(14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = service.loadError, service.rows.isEmpty {
            errorState(err)
        } else if service.rows.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let latest = service.rows.first {
                    headerCard(for: latest)
                        .padding(.horizontal, 16)
                }

                if service.rows.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Previous weeks"))
                            .font(theme.appFont(13, weight: .semibold))
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.horizontal, 16)

                        let previousRows = Array(service.rows.dropFirst())
                        VStack(spacing: 0) {
                            ForEach(Array(previousRows.enumerated()), id: \.element.id) { idx, row in
                                rowView(row)
                                if idx < previousRows.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func headerCard(for row: WeeklyResultRow) -> some View {
        let (glyph, headline) = displayCopy(for: row.rank)
        return VStack(alignment: .leading, spacing: 10) {
            Text(glyph)
                .font(.system(size: 44))
                .accessibilityHidden(true)
            Text(headline)
                .font(theme.appFont(20, weight: .bold))
                .foregroundStyle(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(weekAndXPLine(row))
                .font(theme.appFont(13))
                .foregroundStyle(Color.appSecondaryText)
            Text(String(localized: "Added to your record."))
                .font(theme.appFont(12))
                .foregroundStyle(Color.appTertiaryText)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func rowView(_ row: WeeklyResultRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.weekLabel(row.weekStartDate))
                .font(theme.appFont(15, weight: .medium))
                .foregroundStyle(Color.appPrimaryText)
            Spacer(minLength: 8)
            Text("#\(row.rank)")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color.appPrimaryText)
            Text("·")
                .font(theme.appFont(13))
                .foregroundStyle(Color.appTertiaryText)
            Text(xpLabel(row.xp))
                .font(theme.appFont(13))
                .monospacedDigit()
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(rowAccessibilityLabel(row)))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "No weekly results yet"),
            systemImage: "trophy",
            description: Text(String(localized: "Earn XP this week to claim a placement when results post next Monday."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(String(localized: "Couldn’t load weekly results"))
                .font(theme.appFont(15, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
            Text(message)
                .font(theme.appFont(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(String(localized: "Try again")) {
                Task { await service.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayCopy(for rank: Int) -> (glyph: String, headline: String) {
        switch rank {
        case 1: return ("🥇", String(localized: "You finished #1 last week"))
        case 2: return ("🥈", String(localized: "You finished #2 last week"))
        case 3: return ("🥉", String(localized: "You finished #3 last week"))
        default:
            let headline = String.localizedStringWithFormat(
                String(localized: "You finished #%lld last week"),
                Int64(rank)
            )
            return ("🏅", headline)
        }
    }

    private func weekAndXPLine(_ row: WeeklyResultRow) -> String {
        let week = Self.weekLabel(row.weekStartDate)
        let xp = xpLabel(row.xp)
        return "\(week) · \(xp)"
    }

    private func xpLabel(_ xp: Int) -> String {
        String.localizedStringWithFormat(String(localized: "%lld XP"), Int64(xp))
    }

    private func rowAccessibilityLabel(_ row: WeeklyResultRow) -> String {
        let week = Self.weekLabel(row.weekStartDate)
        return String.localizedStringWithFormat(
            String(localized: "%@, rank %lld, %lld XP"),
            week,
            Int64(row.rank),
            Int64(row.xp)
        )
    }

    /// Renders `"Week of MMM d"` in the user's current locale, e.g. `"Week of May 18"`.
    private static func weekLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMM d")
        let formatted = f.string(from: date)
        return String.localizedStringWithFormat(String(localized: "Week of %@"), formatted)
    }
}

#Preview {
    WeeklyResultsDrawerView()
}
