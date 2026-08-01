import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

/// Pass 2 — result + gap screen. Shows the challenge score and, for each missed
/// question, a card that features the specific parameter the user got wrong at the
/// top ("You missed this"), then the rest of that drug's real `Drug.monitoring`
/// profile below. On a perfect score it shows all three drugs as a "full coverage"
/// teaser (no highlighted gap). Drug facts are never hand-written here.
struct ResultGapStepView: View {
    @ObservedObject var vm: OnboardingViewModel
    @ObservedObject private var drugService = DrugService.shared

    private var total: Int { OnboardingChallenge.items.count }
    private var correct: Int { vm.challengeCorrect }
    private var perfect: Bool { correct >= total }

    /// One card per featured drug. `missedAnswer` is the parameter to spotlight on a
    /// missed question; nil for the perfect-score "full coverage" teaser.
    private struct Feature: Identifiable {
        let drugGenericName: String
        let missedAnswer: String?
        var id: String { drugGenericName }
    }

    private var features: [Feature] {
        if perfect {
            return OnboardingChallenge.items.map {
                Feature(drugGenericName: $0.drugGenericName, missedAnswer: nil)
            }
        }
        return vm.challengeMisses.map {
            Feature(drugGenericName: $0.drugGenericName, missedAnswer: $0.missedAnswer)
        }
    }

    var body: some View {
        OnboardingShell(
            eyebrow: "YOUR RESULTS",
            title: "You got \(correct)/\(total)",
            customTitle: Text("You got ")
                + Text("\(correct)/\(total)").italic().foregroundColor(warmGold),
            bodyText: perfect
                ? "You know your stuff. Here\u{2019}s what full coverage looks like inside MemoRx."
                : "Here\u{2019}s the gap \u{2014} the monitoring you\u{2019}ll lock in with MemoRx.",
            progress: (current: 1, total: OnboardingViewModel.totalSteps),
            primaryTitle: "Continue",
            primaryAction: { vm.advance() },
            backAction: vm.goBack
        ) {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(features) { feature in
                        gapCard(for: feature)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func gapCard(for feature: Feature) -> some View {
        if let drug = resolveDrug(feature.drugGenericName) {
            drugGapCard(drug, missedAnswer: feature.missedAnswer)
        } else {
            unavailableCard(feature.drugGenericName)
        }
    }

    private func resolveDrug(_ genericName: String) -> Drug? {
        let key = genericName.lowercased()
        return drugService.drugs.first { $0.genericName.lowercased() == key }
    }

    // MARK: - Cards

    private func drugGapCard(_ drug: Drug, missedAnswer: String?) -> some View {
        let listItems = monitoringList(drug, excluding: missedAnswer)
        let hasHighlight = !(missedAnswer ?? "").isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            Text(drug.genericName.capitalized)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(warmGold)
            Text(drug.drugClass)
                .font(.system(size: 13))
                .foregroundColor(Color.appSecondaryText)
                .padding(.top, 2)

            if hasHighlight, let missedAnswer {
                missedHighlight(missedAnswer)
                    .padding(.top, 16)
            }

            Divider().opacity(0.3).padding(.vertical, 14)

            Text(hasHighlight ? "FULL MONITORING PROFILE" : "MONITORING")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(warmGold.opacity(0.85))
                .padding(.bottom, 10)

            if listItems.isEmpty {
                Text("See your library for the complete profile.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(listItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(warmGold.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(item)
                                .font(.system(size: 14))
                                .foregroundColor(Color(.label))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topLeading) {
                Color.appCardBackground
                RadialGradient(
                    gradient: Gradient(colors: [warmGold.opacity(0.10), Color.clear]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 140
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(warmGold.opacity(0.20), lineWidth: 1)
        )
    }

    /// The specific parameter the user missed, spotlighted above the full list so it's
    /// the first thing the eye hits.
    private func missedHighlight(_ answer: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(warmGold)
            VStack(alignment: .leading, spacing: 3) {
                Text("YOU MISSED THIS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(warmGold.opacity(0.9))
                Text(answer)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warmGold.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(warmGold.opacity(0.45), lineWidth: 1)
        )
    }

    /// Full monitoring list, minus the featured parameter (exact, normalized match only —
    /// so for warfarin "INR" isn't duplicated, while answers that aren't verbatim bullets
    /// leave the list intact).
    private func monitoringList(_ drug: Drug, excluding answer: String?) -> [String] {
        guard let answer, !answer.isEmpty else { return drug.monitoring }
        let key = normalize(answer)
        return drug.monitoring.filter { normalize($0) != key }
    }

    private func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fallback when the drug catalog hasn't loaded yet (rare — onboarding runs after launch).
    private func unavailableCard(_ genericName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(genericName.capitalized)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundColor(warmGold)
            Text("Monitoring details will appear in your library once it finishes loading.")
                .font(.system(size: 13))
                .foregroundColor(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }
}
