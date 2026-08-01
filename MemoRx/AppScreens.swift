import SwiftUI

struct TodayView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var progress = UserProgressService.shared
    @ObservedObject private var dailyChallenge = DailyChallengeService.shared
    @State private var showMenuLeaderboard = false
    @State private var showMenuDrugRequest = false
    @State private var showMenuSettings = false
    @State private var showMenuHelpFeedback = false

    private var isMenuDestinationPresented: Bool {
        showMenuLeaderboard || showMenuDrugRequest || showMenuSettings || showMenuHelpFeedback
    }

    private var drugs: [Drug] {
        DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
    }

    private var todayDrug: Drug {
        let list = drugs
        if let serverDrug = dailyChallenge.resolvedHighlightDrug(in: list) {
            return serverDrug
        }
        let index = UserProgressService.shared.todaysDrugIndex()
        let count = max(list.count, 1)
        let safeIndex = ((index % count) + count) % count
        return list[safeIndex]
    }

    private var topStreakBadge: some View {
        let tier = StreakFlameTier.tierForTodayToolbar(
            streak: progress.streak,
            hasCompletedDailyQuizToday: progress.hasAwardedDailyQuizXPToday()
        )
        let pill = tier.todayToolbarPillStyle(colorScheme: colorScheme)
        return HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(theme.appFont(14))
                .foregroundStyle(pill.flame)
            Text("\(progress.streak) day\(progress.streak == 1 ? "" : "s")")
                .font(theme.appFont(13, weight: .semibold))
                .foregroundStyle(pill.label)
        }
        .padding(.horizontal, MemoToolbarPillMetrics.horizontalPadding)
        .padding(.vertical, MemoToolbarPillMetrics.verticalPadding)
        .background(
            Capsule()
                .fill(pill.pillFill)
                .shadow(color: pill.glowColor.opacity(pill.glowOpacity), radius: pill.glowRadius, x: 0, y: 1)
        )
        .contentShape(Capsule())
    }

    /// Matches `LibraryView`’s leading/trailing toolbar capsules (`quizCuratorButton`, `flaggedFilterButton`).
    private var todayMenuToolbarButton: some View {
        Menu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openMenuDestination(.leaderboard)
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openMenuDestination(.requestDrug)
            } label: {
                Label("Request a drug", systemImage: "pill.fill")
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openMenuDestination(.helpFeedback)
            } label: {
                Label("Help and feedback", systemImage: "questionmark.circle.fill")
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                openMenuDestination(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(MemoToolbarPillMetrics.iconFont)
                .foregroundStyle(Color(.label))
                .frame(width: MemoToolbarPillMetrics.chipSlotWidth,
                       height: MemoToolbarPillMetrics.chipSlotWidth)
                .memoToolbarIconChipChrome()
        }
        .accessibilityLabel("Menu")
    }

    private enum MenuDestination {
        case leaderboard
        case requestDrug
        case settings
        case helpFeedback
    }

    var body: some View {
        if drugs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Drug library unavailable")
                    .font(theme.appFont(15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let drug = todayDrug

            NavigationStack {
                ZStack {
                    Color.appBackground
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        if dailyChallenge.challengeDrugMissingFromCatalog, dailyChallenge.assignment != nil {
                            Text("Today’s challenge is unavailable — the assigned drug isn’t in your library after refresh. Daily XP is turned off until it’s available.")
                                .font(theme.appFont(13, weight: .semibold))
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.12))
                        }

                        DrugCardView(drug: drug, showBackButton: false, isToday: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, TabContentMetrics.firstCardTopInset)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        todayMenuToolbarButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        topStreakBadge
                    }
                }
                // Always hide the *system* tab bar — `MainTabView` uses `LiquidTabBar` via `safeAreaInset`.
                // `.automatic` here was re-enabling UIKit tab bar chrome after certain navigation transitions.
                .toolbar(.hidden, for: .tabBar)
                .toolbarBackground(.hidden, for: .tabBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showMenuLeaderboard) {
                    LeaderboardView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
                .navigationDestination(isPresented: $showMenuDrugRequest) {
                    RequestDrugView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
                .navigationDestination(isPresented: $showMenuSettings) {
                    SettingsView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
                .navigationDestination(isPresented: $showMenuHelpFeedback) {
                    HelpFeedbackView()
                        .toolbar(.hidden, for: .tabBar)
                        .toolbarBackground(.hidden, for: .tabBar)
                }
            }
            .onAppear {
                LiquidTabBarSuppression.shared.setTodayMenuDrawerOpen(false)
                LiquidTabBarSuppression.shared.setTodayMenuDestinationPresented(isMenuDestinationPresented)
            }
            .onChange(of: isMenuDestinationPresented) { _, presented in
                LiquidTabBarSuppression.shared.setTodayMenuDestinationPresented(presented)
            }
            .onDisappear {
                LiquidTabBarSuppression.shared.setTodayMenuDrawerOpen(false)
                LiquidTabBarSuppression.shared.setTodayMenuDestinationPresented(false)
            }
        }
    }

    private func openMenuDestination(_ destination: MenuDestination) {
        switch destination {
        case .leaderboard:
            showMenuLeaderboard = true
        case .requestDrug:
            showMenuDrugRequest = true
        case .settings:
            showMenuSettings = true
        case .helpFeedback:
            showMenuHelpFeedback = true
        }
    }
}

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("highContrastEnabled") private var highContrastEnabled = false
    @State private var drugs: [Drug] = []
    @State private var searchText = ""
    @State private var showFlaggedOnly = false
    @State private var showQuizCurator = false
    @FocusState private var searchFieldFocused: Bool
    @StateObject private var progress = UserProgressService.shared
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var showPaywall = false

    private var groupedByCollection: [DrugCollection: [Drug]] {
        Dictionary(grouping: drugs, by: \.collection)
    }

    private var sortedCollections: [DrugCollection] {
        groupedByCollection.keys.sorted { collectionDisplayName($0) < collectionDisplayName($1) }
    }

    var filteredDrugs: [Drug] {
        if searchText.isEmpty { return [] }
        return drugs.filter { matchesSearch($0, query: searchText) }
    }

    private var flaggedDrugs: [Drug] {
        drugs
            .filter { progress.isDrugFlagged($0.id) }
            .sorted { $0.genericName.localizedCaseInsensitiveCompare($1.genericName) == .orderedAscending }
    }

    private var flaggedDrugsFilteredBySearch: [Drug] {
        if searchText.isEmpty { return flaggedDrugs }
        return flaggedDrugs.filter { matchesSearch($0, query: searchText) }
    }

    private func matchesSearch(_ drug: Drug, query: String) -> Bool {
        let normalizedQuery = query.lowercased()
        return drug.genericName.lowercased().contains(normalizedQuery) ||
            drug.brandNames.joined(separator: " ").lowercased().contains(normalizedQuery)
    }

    private func toggleFlaggedOnlyMode() {
        showFlaggedOnly.toggle()
        searchText = ""
        searchFieldFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var flaggedFilterButton: some View {
        Button {
            toggleFlaggedOnlyMode()
        } label: {
            Image(systemName: showFlaggedOnly ? "flag.fill" : "flag")
                .font(MemoToolbarPillMetrics.iconFont)
                .foregroundStyle(showFlaggedOnly ? .orange : Color(.label))
                .frame(width: MemoToolbarPillMetrics.chipSlotWidth, height: MemoToolbarPillMetrics.chipSlotWidth)
                .memoToolbarIconChipChrome()
        }
    }

    private var quizCuratorButton: some View {
        Button {
            showQuizCurator = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(MemoToolbarPillMetrics.iconFont)
                .foregroundStyle(Color(.label))
                .frame(width: MemoToolbarPillMetrics.chipSlotWidth, height: MemoToolbarPillMetrics.chipSlotWidth)
                .memoToolbarIconChipChrome()
        }
        .accessibilityLabel("Open quiz curator")
    }

    func badgeTier(for collectionDrugs: [Drug]) -> (label: String, color: Color)? {
        guard !collectionDrugs.isEmpty else { return nil }

        let masteredCount = collectionDrugs.filter { drug in
            let scores = UserProgressService.shared.drugScores[drug.id] ?? []
            return scores.contains { $0 >= 80 }
        }.count

        let pct = Double(masteredCount) / Double(collectionDrugs.count)

        switch pct {
        case 0.80...1.0: return ("MASTERED", Color.purple)
        case 0.50..<0.80: return ("STRONG", Color(red: 1.0, green: 0.84, blue: 0.0))
        case 0.25..<0.50: return ("MID", Color(.systemGray))
        case 0.01..<0.25: return ("WEAK", Color(.systemGray3))
        default: return nil
        }
    }

    private var browseSearchCapsuleWidth: CGFloat {
        UIScreen.main.bounds.width / 3
    }

    private var browseLiquidGlassSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(theme.appFont(14, weight: .medium))
                .foregroundStyle(Color.appSecondaryText)

            TextField("Search drugs...", text: $searchText)
                .focused($searchFieldFocused)
                .textFieldStyle(.plain)
                .font(theme.appFont(14))
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(theme.appFont(15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: browseSearchCapsuleWidth)
        .background {
            if highContrastEnabled {
                Capsule(style: .continuous)
                    .fill(Color.appInputBackground)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.appTertiaryText.opacity(0.45), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
            } else {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            }
        }
    }

    var body: some View {
        NavigationStack { libraryContent }
            .onAppear {
                drugs = DrugService.shared.drugs
            }
    }

    private var libraryContent: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if showFlaggedOnly {
                        flaggedOnlySection
                    } else {
                        if !searchText.isEmpty {
                            searchResultsSection
                        }

                        if searchText.isEmpty {
                            collectionsSection
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, TabContentMetrics.firstCardTopInset)
                .padding(.bottom, 64)
            }
            .scrollDismissesKeyboard(.interactively)
            .drugListScrollEdgeFade()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                quizCuratorButton
            }
            ToolbarItem(placement: .principal) {
                browseLiquidGlassSearchBar
            }
            ToolbarItem(placement: .topBarTrailing) {
                flaggedFilterButton
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showQuizCurator) {
            QuizCuratorView(allDrugs: drugs)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if filteredDrugs.isEmpty {
            Text("No results for \"\(searchText)\"")
                .font(theme.appFont(14))
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(filteredDrugs) { drug in
                    searchResultRow(for: drug)
                }
            }
        }
    }

    private var collectionsSection: some View {
        ForEach(sortedCollections, id: \.self) { collection in
            let items = groupedByCollection[collection] ?? []
            NavigationLink {
                CollectionDrugsView(collection: collection, drugs: items)
            } label: {
                collectionRow(collection: collection, items: items)
            }
        }
    }

    @ViewBuilder
    private var flaggedOnlySection: some View {
        if flaggedDrugsFilteredBySearch.isEmpty {
            Text(searchText.isEmpty ? "No flagged drugs yet." : "No flagged results for \"\(searchText)\"")
                .font(theme.appFont(14))
                .foregroundStyle(Color.appSecondaryText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(flaggedDrugsFilteredBySearch) { drug in
                    flaggedDrugRow(for: drug)
                }
            }
        }
    }

    private func flaggedDrugRow(for drug: Drug) -> some View {
        NavigationLink(destination: DrugCardView(drug: drug, showBackButton: true, isToday: false)) {
            let isFlagged = progress.isDrugFlagged(drug.id)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(collectionColor(subCollectionDisplayName(drug.subCollection)))
                    .frame(width: 4)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drug.genericName.capitalized)
                            .font(theme.appFont(17, weight: .semibold))
                            .foregroundStyle(Color.appPrimaryText)
                        Text(drug.brandNames.first ?? "")
                            .font(theme.appFont(13))
                            .foregroundStyle(Color.appSecondaryText)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            progress.toggleDrugFlag(drug.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: isFlagged ? "flag.fill" : "flag")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isFlagged ? .orange : Color.appTertiaryText)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .minimumHitTarget()
                        .accessibilityLabel(isFlagged ? "Unflag drug" : "Flag drug")

                        Image(systemName: "chevron.right")
                            .font(theme.appFont(14))
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }
                .padding(16)
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private func searchResultRow(for drug: Drug) -> some View {
        NavigationLink(destination: DrugCardView(drug: drug, showBackButton: true, isToday: false)) {
            let isFlagged = progress.isDrugFlagged(drug.id)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(drug.genericName.capitalized)
                        .font(theme.appFont(16, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text(drug.brandNames.first ?? "")
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        progress.toggleDrugFlag(drug.id)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: isFlagged ? "flag.fill" : "flag")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFlagged ? Color.orange : Color.appTertiaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .accessibilityLabel(isFlagged ? "Unflag drug" : "Flag drug")

                    Image(systemName: "chevron.right")
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .padding(14)
            .background(Color.appCardBackground)
            .cornerRadius(14)
        }
    }

    private func collectionRow(collection: DrugCollection, items: [Drug]) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(collectionColor(collectionDisplayName(collection)))
                .frame(width: 4)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collectionDisplayName(collection))
                        .font(theme.appFont(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    let subCount = Set(items.map(\.subCollection)).count
                    Text("\(items.count) drugs · \(subCount) \(subCount == 1 ? "class" : "classes")")
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(theme.appFont(14))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(16)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct CollectionDrugsView: View {
    @Environment(\.appTheme) private var theme
    let collection: DrugCollection
    let drugs: [Drug]
    @ObservedObject private var progress = UserProgressService.shared

    private var groupedBySubCollection: [SubCollection: [Drug]] {
        Dictionary(grouping: drugs, by: \.subCollection)
    }

    private var sortedSubCollections: [SubCollection] {
        let order = KnownSubCollection.preferredOrder
        return groupedBySubCollection.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return subCollectionDisplayName(a) < subCollectionDisplayName(b)
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sortedSubCollections, id: \.self) { sub in
                        let items = groupedBySubCollection[sub] ?? []
                        NavigationLink {
                            SubCollectionDrugsView(subCollection: sub, drugs: items)
                        } label: {
                            subCollectionRow(subCollection: sub, items: items)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .drugListScrollEdgeFade()
        }
        .background(SubCollectionNavigationBarChrome())
        .navigationTitle(collectionDisplayName(collection))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .onAppear { LiquidTabBarSuppression.shared.libraryStackDidPush() }
        .onDisappear { LiquidTabBarSuppression.shared.libraryStackDidPop() }
    }

    private func subCollectionRow(subCollection: SubCollection, items: [Drug]) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(collectionColor(subCollectionDisplayName(subCollection)))
                .frame(width: 4)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subCollectionDisplayName(subCollection))
                        .font(theme.appFont(17, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text("\(items.count) \(items.count == 1 ? "drug" : "drugs")")
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(theme.appFont(14))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(16)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

func collectionColor(_ name: String) -> Color {
    if let hex = KnownSubCollection.colors[name] {
        return Color(hex: hex)
    }
    return Color(hex: "888888")
}
