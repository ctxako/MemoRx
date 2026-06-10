import SwiftUI
import UIKit

private struct LibraryRowCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

private extension View {
    func libraryRowCardStyle() -> some View {
        modifier(LibraryRowCardStyle())
    }
}

private extension View {
    func growthHeroPlate() -> some View {
        modifier(GrowthHeroPlateModifier())
    }

    func growthSecondaryCard() -> some View {
        modifier(GrowthSecondaryCardModifier())
    }

    func growthGroupedDrugWell() -> some View {
        modifier(GrowthGroupedDrugWellModifier())
    }
}

private struct GrowthHeroPlateModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

private struct GrowthSecondaryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

private struct GrowthGroupedDrugWellModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appInputBackground.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GrowthTickerEntry: Identifiable {
    let id: String
    let symbolName: String
    let headline: String
    var footnote: String?
    var handlesNavigation: Bool
    var onTap: () -> Void
    var streak7Day: Int?
    var examStudyFraction: Double?
    var examDate: Date?
    var quizPercent: Int?
    var quizDrugName: String?
    var quizDrugNameForOpen: String?
    var quizXP: Int? = nil
    /// Signed calendar days until NAPLEX (`ProgressDashboardView` naplex ticker only); `nil` for other entries.
    var examDaysUntil: Int? = nil
}

private struct GrowthQuizCoverItem: Identifiable {
    let drug: Drug
    let source: UserProgressService.QuizSource

    var id: String { "\(drug.id)#\(source.rawValue)" }
}

// MARK: - Ticker card subviews

/// Hero numerals on Growth ticker rows: serif + semibold + kerning; larger than body type for scanability.
private enum GrowthTickerHeroNumberFont {
    static let font = Font.system(size: 64, weight: .semibold, design: .serif)
    static let kerning: CGFloat = 0.35
}

/// Same vertical thickness for streak day segments and the NAPLEX study bar on the Growth ticker.
private enum GrowthStreakAndNaplexBarMetrics {
    static let segmentHeight: CGFloat = 8
}

// MARK: - Growth streak ticker watermark
//
// Tier model: `StreakFlameTier.swift`. This file only hosts the animated watermark used on the Growth ticker card.

/// Top-right watermark flame for the Growth Streak ticker. Reads the current tier from `streak`
/// and renders a blurred glow layer + a palette-rendered `flame.fill` that breathes via a single
/// `TimelineView`. `celebrationToken` is a monotonically increasing trigger — when it changes,
/// the view runs a one-shot spring scale bump for tier-up moments.
private struct StreakFlameWatermark: View {
    let streak: Int
    let colorScheme: ColorScheme
    let celebrationToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrationScale: CGFloat = 1.0

    private var tier: StreakFlameTier { .from(streak: streak) }
    private var style: StreakFlameStyle { tier.style }
    private static let symbolSize: CGFloat = 88

    /// From the 3rd tier (ember, `rank == 2`) upward, stretch the breath cycle so the flame feels calmer as it intensifies.
    private var breathingPulsePeriod: Double {
        let base = style.pulsePeriod
        guard tier.rank >= 2 else { return base }
        return base * 1.55
    }

    var body: some View {
        flameLayer
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 6)
            .padding(.top, 6)
            .scaleEffect(celebrationScale, anchor: .topTrailing)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onChange(of: celebrationToken) { _, _ in
                triggerCelebrationBump()
            }
    }

    @ViewBuilder
    private var flameLayer: some View {
        if tier == .dormant || reduceMotion || style.pulsePeriod == 0 {
            staticFlame
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * 2 * .pi / breathingPulsePeriod)
                let scale = 1.0 + style.pulseAmount * CGFloat(phase)
                let opacityBreath = 1.0 + 0.08 * phase
                composedFlame(scale: scale, opacityMultiplier: opacityBreath)
            }
        }
    }

    private var staticFlame: some View {
        composedFlame(scale: 1.0, opacityMultiplier: 1.0)
    }

    private func composedFlame(scale: CGFloat, opacityMultiplier: Double) -> some View {
        ZStack(alignment: .topTrailing) {
            if style.glowRadius > 0 {
                Image(systemName: "flame.fill")
                    .font(.system(size: Self.symbolSize, weight: .ultraLight))
                    .foregroundStyle(style.glowColor)
                    .blur(radius: style.glowRadius)
                    .opacity(style.glowOpacity(for: colorScheme) * opacityMultiplier)
                    .scaleEffect(1.0 + (scale - 1.0) * 1.6, anchor: .center)
            }

            paletteFlame
                .opacity(style.opacity(for: colorScheme) * opacityMultiplier)
                .scaleEffect(scale, anchor: .center)
        }
    }

    @ViewBuilder
    private var paletteFlame: some View {
        if tier == .dormant {
            // Preserve the exact original look at streak 0: monochrome, low-opacity grey.
            Image(systemName: "flame.fill")
                .font(.system(size: Self.symbolSize, weight: .ultraLight))
                .foregroundStyle(style.baseColor)
        } else {
            Image(systemName: "flame.fill")
                .font(.system(size: Self.symbolSize, weight: .ultraLight))
                .symbolRenderingMode(.palette)
                .foregroundStyle(style.baseColor, style.coreColor)
        }
    }

    private func triggerCelebrationBump() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            celebrationScale = 1.18
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                celebrationScale = 1.0
            }
        }
    }
}

/// Top-right watermark sparkles for the "Today's drug" ticker. Mirrors `StreakFlameWatermark`'s
/// 88pt symbol size, top-trailing anchor, and 6pt insets so slides 1 and 3 share a visual rhythm.
/// Static (no breathing) because the sparkles glyph is purely decorative — unlike the flame, it
/// carries no tier semantics.
private struct QuizSparklesWatermark: View {
    let colorScheme: ColorScheme
    private static let symbolSize: CGFloat = 88

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: Self.symbolSize, weight: .ultraLight))
            .foregroundStyle(Color.appPrimaryText.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 6)
            .padding(.top, 6)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Subtle top-right mesh gradient glow rendered behind each `tickerRow` slide.
/// `accentColor` is the per-card hue (orange for streak, blue for NAPLEX, green for completed,
/// white for the "today's drug" open prompt).
///
/// Why a single interior bright point + all-`.clear` outer ring: when any edge/corner lattice
/// point carries non-zero opacity, the gradient is non-zero at the bounds and the blur kernel
/// can't fade past them — you see a visible hard line parallel to whichever edge carried weight
/// (this is what produced the bottom + left lines in the first pass). Keeping every outer point
/// clear forces opacity to drop to 0 before reaching the bounds, so the glow tapers smoothly.
///
/// The bright point is anchored at `(0.78, 0.28)` for every card to match the streak card's
/// `StreakFlameWatermark` position (top-trailing of the slide).
private struct TickerCardGlowBackground: View {
    let accentColor: Color
    let colorScheme: ColorScheme

    private static let heartPoint: SIMD2<Float> = [0.78, 0.28]

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0],   [0.5, 0.0],  [1.0, 0.0],
                [0.0, 0.5],   Self.heartPoint, [1.0, 0.5],
                [0.0, 1.0],   [0.5, 1.0],  [1.0, 1.0]
            ],
            colors: [
                .clear, .clear, .clear,
                .clear, accentColor.opacity(0.34), .clear,
                .clear, .clear, .clear
            ]
        )
        .blur(radius: 26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TickerIconTile: View {
    let symbolName: String
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(accent.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                )
                .frame(width: 52, height: 52)
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accent)
        }
    }
}

private struct StreakTickerCard: View {
    @Environment(\.appTheme) private var theme
    let entry: GrowthTickerEntry
    let colorScheme: ColorScheme
    /// Increments when the dashboard detects a tier promotion. The watermark listens for changes
    /// and runs a one-shot spring scale bump (paired with a light haptic fired by the dashboard).
    var celebrationToken: Int = 0

    private var filledCount: Int { min(entry.streak7Day ?? 0, 7) }

    private func streakSubtitle(for days: Int) -> String {
        switch days {
        case 0:
            return String(localized: "Streak")
        case 1:
            return String(localized: "1 day streak")
        default:
            return String.localizedStringWithFormat(String(localized: "%lld days streak"), Int64(days))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                StreakFlameWatermark(
                    streak: entry.streak7Day ?? 0,
                    colorScheme: colorScheme,
                    celebrationToken: celebrationToken
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(entry.streak7Day ?? 0)")
                            .font(GrowthTickerHeroNumberFont.font)
                            .kerning(GrowthTickerHeroNumberFont.kerning)
                            .foregroundStyle(Color.appPrimaryText)
                            .lineLimit(1)
                        Text((entry.streak7Day ?? 0) == 1 ? "day" : "days")
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.orange)
                    }
                    Text(streakSubtitle(for: entry.streak7Day ?? 0))
                        .font(theme.appFont(14))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: GrowthStreakAndNaplexBarMetrics.segmentHeight / 2, style: .continuous)
                        .fill(i < filledCount ? Color.orange : Color.appTertiaryText.opacity(0.22))
                        .frame(maxWidth: .infinity)
                        .frame(height: GrowthStreakAndNaplexBarMetrics.segmentHeight)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuizDoneTickerCard: View {
    @Environment(\.appTheme) private var theme
    let entry: GrowthTickerEntry
    let colorScheme: ColorScheme

    private var scoreColor: Color {
        guard let pct = entry.quizPercent else { return Color.appPrimaryText }
        if pct >= 80 { return .green }
        if pct >= 60 { return .orange }
        return .red
    }

    private var arcFraction: Double {
        Double(entry.quizPercent ?? 0) / 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(entry.quizPercent ?? 0)%")
                            .font(GrowthTickerHeroNumberFont.font)
                            .kerning(GrowthTickerHeroNumberFont.kerning)
                            .foregroundStyle(scoreColor)
                            .lineLimit(1)
                    }
                    if let drug = entry.quizDrugName, !drug.isEmpty {
                        Text(drug)
                            .font(theme.appFont(17, weight: .semibold))
                            .foregroundStyle(Color.appPrimaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.appTertiaryText.opacity(0.18), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: arcFraction)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: arcFraction)
                    Text("\(entry.quizPercent ?? 0)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(scoreColor)
                }
                .frame(width: 64, height: 64)
                .padding(.top, 6)
                .padding(.trailing, 4)
            }

            Spacer(minLength: 4)

            HStack {
                if let foot = entry.footnote {
                    Text(foot)
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if let xp = entry.quizXP, xp > 0 {
                    Text("+\(xp) XP")
                        .font(theme.appFont(12, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Text("Tap to review →")
                    .font(theme.appFont(11))
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuizOpenTickerCard: View {
    @Environment(\.appTheme) private var theme
    let entry: GrowthTickerEntry
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                QuizSparklesWatermark(colorScheme: colorScheme)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.quizDrugNameForOpen ?? String(localized: "Quiz ready"))
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .kerning(GrowthTickerHeroNumberFont.kerning)
                        .foregroundStyle(Color.appPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Today's drug")
                        .font(theme.appFont(14))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Text("Start quiz →")
                    .font(theme.appFont(12, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.appPrimaryText)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExamTickerCard: View {
    @Environment(\.appTheme) private var theme
    let entry: GrowthTickerEntry
    let colorScheme: ColorScheme

    private var daysValue: Int? { entry.examDaysUntil }

    private var studyFraction: Double { entry.examStudyFraction ?? 0.0 }

    /// Same hue as the NAPLEX study bar. Named distinctly so it is never confused with the
    /// environment’s accent/tint (Growth lives under `MainTabView`’s `.tint(Color(.label))`, which
    /// otherwise keeps hero `Text` on label-colored ink inside `Button` labels).
    private var naplexUrgencyColor: Color {
        guard let d = daysValue else { return Color.appSecondaryText }
        if d < 0 { return Color.appSecondaryText }
        if d > 60 { return Color(hue: 0.58, saturation: 0.85, brightness: 0.95) }
        if d > 14 { return .orange }
        return .red
    }

    private var pillFillColor: Color {
        guard let d = daysValue else { return .blue }
        if d < 0 { return Color(.systemGray) }
        return d <= 14 ? .red : .blue
    }

    private var formattedExamDate: String? {
        guard let date = entry.examDate else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Group {
                    if let d = daysValue, d > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text("\(d)")
                                    .font(GrowthTickerHeroNumberFont.font)
                                    .kerning(GrowthTickerHeroNumberFont.kerning)
                                    .foregroundStyle(Color.appPrimaryText)
                                    .foregroundColor(Color.appPrimaryText)
                                    .lineLimit(1)
                                Text(d == 1 ? String(localized: "day") : String(localized: "days"))
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundStyle(naplexUrgencyColor)
                                    .foregroundColor(naplexUrgencyColor)
                            }
                            Text(String(localized: "until NAPLEX exam"))
                                .font(theme.appFont(14))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    } else if let d = daysValue, d == 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Today"))
                                .font(GrowthTickerHeroNumberFont.font)
                                .kerning(GrowthTickerHeroNumberFont.kerning)
                                .foregroundStyle(Color.appPrimaryText)
                                .foregroundColor(Color.appPrimaryText)
                                .lineLimit(1)
                            Text(String(localized: "NAPLEX exam"))
                                .font(theme.appFont(14))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    } else if let d = daysValue, d < 0 {
                        let ago = -d
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text("\(ago)")
                                    .font(GrowthTickerHeroNumberFont.font)
                                    .kerning(GrowthTickerHeroNumberFont.kerning)
                                    .foregroundStyle(Color.appPrimaryText)
                                    .foregroundColor(Color.appPrimaryText)
                                    .lineLimit(1)
                                Text(ago == 1 ? String(localized: "day ago") : String(localized: "days ago"))
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundStyle(naplexUrgencyColor)
                                    .foregroundColor(naplexUrgencyColor)
                            }
                            Text(String(localized: "Update your exam date"))
                                .font(theme.appFont(14))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    } else if !entry.headline.isEmpty {
                        Text(entry.headline)
                            .font(theme.appFont(17, weight: .semibold))
                            .foregroundStyle(Color.appPrimaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                // Scoped here (not the whole card) so tab `.tint(Color(.label))` does not force hero
                // numerals to label ink, without changing the date pill or bar fills.
                .tint(naplexUrgencyColor)

                Spacer()

                HStack(spacing: 6) {
                    Text("\u{1F4C5}")
                        .font(.system(size: 17))
                    Text(formattedExamDate ?? String(localized: "Set date"))
                        .font(theme.appFont(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(pillFillColor, in: Capsule())
                .minimumHitTarget()
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let barH = GrowthStreakAndNaplexBarMetrics.segmentHeight
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: barH / 2, style: .continuous)
                            .fill(Color.appTertiaryText.opacity(0.18))
                        RoundedRectangle(cornerRadius: barH / 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [naplexUrgencyColor.opacity(0.7), naplexUrgencyColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * CGFloat(studyFraction), studyFraction > 0 ? 4 : 0))
                    }
                }
                .frame(height: GrowthStreakAndNaplexBarMetrics.segmentHeight)
                .animation(.easeOut(duration: 0.8), value: studyFraction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Page dots for the Growth ticker — same visual language as `DrugProgressIndicator` (library drug card): gray capsule, equal-size circles.
private struct GrowthTickerDotCapsuleIndicator: View {
    let pageCount: Int
    let currentPage: Int

    /// Matches `IndicatorMetrics.collapsed()` in `DrugProgressIndicator.swift`.
    private enum Metrics {
        static let dotSpacing: CGFloat = 7
        static let capsuleHPadding: CGFloat = 11
        static let capsuleVPadding: CGFloat = 6
        static let dotDiameter: CGFloat = 6
    }

    var body: some View {
        HStack(spacing: Metrics.dotSpacing) {
            ForEach(0..<pageCount, id: \.self) { idx in
                Circle()
                    .fill(idx == currentPage ? Color(.label) : Color(.tertiaryLabel).opacity(0.45))
                    .frame(width: Metrics.dotDiameter, height: Metrics.dotDiameter)
            }
        }
        .padding(.horizontal, Metrics.capsuleHPadding)
        .padding(.vertical, Metrics.capsuleVPadding)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: currentPage)
    }
}

// MARK: - Growth ticker UIKit pager

/// UIKit-backed horizontal pager (`UIScrollView` + `UIHostingController`). Keeps `Binding` page
/// index in sync for the shared `TickerCardGlowBackground` accent.
private struct GrowthTickerUIKitPager: UIViewRepresentable {
    @Binding var selection: Int
    var pageCount: Int
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var layoutKey: String
    var pages: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.contentInsetAdjustmentBehavior = .never

        let hosting = UIHostingController(rootView: AnyView(EmptyView()))
        hosting.view.backgroundColor = .clear
        scrollView.addSubview(hosting.view)

        context.coordinator.hostingController = hosting
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.binding = $selection
        context.coordinator.pageCount = pageCount
        context.coordinator.pageHeight = pageHeight

        let w = max(scrollView.bounds.width, pageWidth, 1)

        let layoutChanged = context.coordinator.layoutKey != layoutKey
            || abs(context.coordinator.lastPageWidth - w) > 0.5
        if layoutChanged {
            context.coordinator.layoutKey = layoutKey
            context.coordinator.lastPageWidth = w
            context.coordinator.hostingController?.rootView = pages
        }

        let pagesWidth = w * CGFloat(max(pageCount, 1))
        context.coordinator.hostingController?.view.frame = CGRect(x: 0, y: 0, width: pagesWidth, height: pageHeight)
        scrollView.contentSize = CGSize(width: pagesWidth, height: pageHeight)

        scrollView.bounces = pageCount > 1
        scrollView.alwaysBounceHorizontal = pageCount > 1
        scrollView.isPagingEnabled = pageCount > 0

        if layoutChanged, pageCount > 0 {
            let clamped = min(max(selection, 0), pageCount - 1)
            scrollView.setContentOffset(CGPoint(x: CGFloat(clamped) * w, y: 0), animated: false)
        } else if pageCount > 0 && !scrollView.isDragging && !scrollView.isDecelerating {
            let clamped = min(max(selection, 0), pageCount - 1)
            let targetX = CGFloat(clamped) * w
            if abs(scrollView.contentOffset.x - targetX) > 2 {
                scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)
            }
        }

        if pageCount > 0 {
            let idx = min(max(selection, 0), pageCount - 1)
            scrollView.accessibilityLabel = String(localized: "Growth reminder cards")
            scrollView.accessibilityValue = String.localizedStringWithFormat(
                String(localized: "Page %lld of %lld"),
                Int64(idx + 1),
                Int64(pageCount)
            )
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var binding: Binding<Int>?
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<AnyView>?
        var pageCount: Int = 0
        var pageHeight: CGFloat = 148
        var layoutKey: String = ""
        var lastPageWidth: CGFloat = 0

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard pageCount > 0 else { return }
            let w = scrollView.bounds.width
            guard w > 0 else { return }
            let page = min(max(Int((scrollView.contentOffset.x + w * 0.5) / w), 0), pageCount - 1)
            if binding?.wrappedValue != page {
                binding?.wrappedValue = page
            }
        }
    }
}

// MARK: - Main view

struct ProgressDashboardView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @StateObject private var progress = UserProgressService.shared
    @AppStorage("userName") private var userName = ""

    /// Persisted raw value of the last `StreakFlameTier` we celebrated. Empty on first launch of
    /// this feature — in that case we seed silently without firing a haptic, so existing users
    /// don't get a surprise celebration for the tier they're already at.
    @AppStorage("growth.streak.flame.lastSeenTier") private var lastSeenStreakFlameTierRaw: String = ""

    @State private var showNaplexEdit = false
    @State private var editDate: Date = Date()
    @State private var quizCoverItem: GrowthQuizCoverItem?

    @State private var showDailyArchive = false
    @State private var showWeeklyResults = false
    /// Captured when a row in the daily archive sheet is tapped. We open `quizCoverItem` only after
    /// the sheet dismisses so the sheet and `.fullScreenCover` don't race for presentation.
    @State private var pendingDailyArchiveDrug: Drug?

    @State private var tickerPage = 0

    @State private var xpBarShownRatio: CGFloat = 0

    /// Monotonically incrementing token consumed by `StreakFlameWatermark` to trigger the one-shot
    /// scale bump when the user crosses a streak tier threshold. Paired with a light haptic.
    @State private var streakFlameCelebrationToken: Int = 0

    private var orderedDrugs: [Drug] {
        DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
    }

    private var allDrugs: [Drug] {
        DrugService.shared.drugs
    }

    private var dueDrugs: [Drug] {
        progress.drugsForReview(from: allDrugs)
    }

    private var prioritizedDueDrugs: [Drug] {
        dueDrugs.sorted {
            let lhs = progress.averageScore(for: $0)
            let rhs = progress.averageScore(for: $1)
            if lhs == rhs {
                return $0.genericName.localizedCaseInsensitiveCompare($1.genericName) == .orderedAscending
            }
            return lhs < rhs
        }
    }

    private var todayDrug: Drug? {
        guard !orderedDrugs.isEmpty else { return nil }
        let count = orderedDrugs.count
        let idx = loopingIndex(progress.todaysDrugIndex(), count: count)
        return orderedDrugs[idx]
    }

    private func loopingIndex(_ raw: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((raw % count) + count) % count
    }

    private var naplexDate: Date? {
        guard let ts = UserDefaults.standard.object(forKey: "naplexDate") as? Double else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private var naplexDayOffsetSigned: Int? {
        guard let exam = naplexDate else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: exam)
        return cal.dateComponents([.day], from: today, to: target).day
    }

    private var trimmedDisplayFirstName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private var friendlyFirstName: String {
        let t = trimmedDisplayFirstName
        return t.isEmpty ? String(localized: "Friend") : t
    }

    private var displayName: String { friendlyFirstName }

    private func greetingPhrase(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 5 {
            return String(localized: "Good night")
        }
        if hour < 12 {
            return String(localized: "Good morning")
        }
        if hour < 17 {
            return String(localized: "Good afternoon")
        }
        if hour < 22 {
            return String(localized: "Good evening")
        }
        return String(localized: "Good night")
    }

    private var tickerEntries: [GrowthTickerEntry] {
        var out: [GrowthTickerEntry] = []

        out.append(GrowthTickerEntry(
            id: "streak",
            symbolName: "flame.fill",
            headline: "",
            footnote: nil,
            handlesNavigation: false,
            onTap: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            streak7Day: max(progress.streak, 0)
        ))

        if let napOffset = naplexDayOffsetSigned {
            let elapsed = napOffset > 0 ? Double(max(365 - napOffset, 0)) / 365.0 : 1.0
            out.append(GrowthTickerEntry(
                id: "naplex",
                symbolName: "calendar",
                headline: "",
                footnote: nil,
                handlesNavigation: true,
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    openNaplexEditor()
                },
                examStudyFraction: min(max(elapsed, 0), 1),
                examDate: naplexDate,
                examDaysUntil: napOffset
            ))
        }

        guard let td = todayDrug else { return out }

        if progress.hasAwardedDailyQuizXPToday() {
            let pctFromLatestDaily = progress.latestDailyQuizPercent(for: td)
            let pct = pctFromLatestDaily ?? progress.averageScore(for: td)
            let dailyDetails: String
            let dailyXP: Int
            if let session = progress.lastDrugQuizSession, session.drugId == td.id {
                dailyDetails = String.localizedStringWithFormat(
                    String(localized: "%lld of %lld correct · %@"),
                    Int64(session.correctCount),
                    Int64(session.totalCount),
                    relativeSessionLabel(for: Date(timeIntervalSince1970: session.timestamp))
                )
                dailyXP = progress.calculateQuizXP(correct: session.correctCount, total: session.totalCount)
            } else {
                let fallbackTotal = 7
                let fallbackCorrect = Int(round(Double(pct * fallbackTotal) / 100.0))
                dailyDetails = String.localizedStringWithFormat(
                    String(localized: "%lld of %lld correct"),
                    Int64(fallbackCorrect),
                    Int64(fallbackTotal)
                )
                dailyXP = progress.calculateQuizXP(correct: fallbackCorrect, total: fallbackTotal)
            }
            out.append(GrowthTickerEntry(
                id: "daily.done",
                symbolName: "checkmark.circle.fill",
                headline: "",
                footnote: dailyDetails,
                handlesNavigation: true,
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quizCoverItem = GrowthQuizCoverItem(drug: td, source: .daily)
                },
                quizPercent: pct,
                quizDrugName: td.genericName.capitalized,
                quizXP: dailyXP
            ))
        } else {
            out.append(GrowthTickerEntry(
                id: "daily.open",
                symbolName: "sparkles",
                headline: "",
                footnote: String(localized: "Tap to start — it only counts once toward your leaderboard XP."),
                handlesNavigation: true,
                onTap: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    quizCoverItem = GrowthQuizCoverItem(drug: td, source: .daily)
                },
                quizDrugNameForOpen: td.genericName.capitalized
            ))
        }

        return out
    }

    private func relativeSessionLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        heroSection
                        momentumSection
                        dueForReviewBody
                        dailyArchiveSection
                        dailyAttemptHistorySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, TabContentMetrics.firstCardTopInset)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
                .drugListScrollEdgeFade()
                .background(Color.appBackground)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    growthPrincipalGreeting
                }
            }
        }
        .fullScreenCover(item: $quizCoverItem) { item in
            QuizView(drug: item.drug, source: item.source)
        }
        .overlay {
            if showNaplexEdit {
                naplexEditOverlay
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: showNaplexEdit)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .onAppear {
            syncTickerPageWithEntryCount()
            hydrateXpBarRatio(animated: !accessibilityReduceMotion)
            evaluateStreakFlameTierTransition()
        }
        .task {
            // Pull authoritative XP/weekly_xp from Supabase whenever Growth appears so the
            // total displayed here matches the Leaderboard. Previously local state could
            // be stale (e.g. zero) after a sign-out / sign-in cycle when the user had
            // server XP but `hydrateFromServerIfNeeded` had been skipped.
            await progress.refreshAuthoritativeProgressFromServer()
            hydrateXpBarRatio(animated: !accessibilityReduceMotion)
        }
        .onChange(of: tickerEntries.count) { _, _ in
            syncTickerPageWithEntryCount()
        }
        .onChange(of: progress.streak) { _, _ in
            evaluateStreakFlameTierTransition()
        }
        .onChange(of: showNaplexEdit) { _, open in
            LiquidTabBarSuppression.shared.setProgressCardEditorOpen(open)
        }
        .onChange(of: accessibilityReduceMotion) { _, reduced in
            hydrateXpBarRatio(animated: !reduced)
        }
    }

    /// Detects whether the user has climbed to a new `StreakFlameTier` since we last persisted one.
    /// Fires a light haptic + increments `streakFlameCelebrationToken` (which the watermark uses to
    /// run a one-shot spring scale bump) only on *promotions*; demotions silently re-sync, and the
    /// very first invocation on a non-empty store seeds without celebration.
    private func evaluateStreakFlameTierTransition() {
        let current = StreakFlameTier.from(streak: progress.streak)

        // First time this device sees the feature — seed quietly so an existing 30-day user doesn't
        // get a surprise haptic for a tier they've long been at.
        guard !lastSeenStreakFlameTierRaw.isEmpty else {
            lastSeenStreakFlameTierRaw = current.rawValue
            return
        }

        let stored = StreakFlameTier(rawValue: lastSeenStreakFlameTierRaw) ?? .dormant

        if current.rank > stored.rank {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            streakFlameCelebrationToken &+= 1
        }

        if current != stored {
            lastSeenStreakFlameTierRaw = current.rawValue
        }
    }

    /// Stacked greeting rendered in the navigation bar's principal slot so Growth shares the same
    /// top chrome footprint as Today and Library.
    private var growthPrincipalGreeting: some View {
        let timeLabelSize: CGFloat = 10.5
        let nameSize: CGFloat = 56 * 0.85
        let timeColor = Color(red: 0x4a / 255, green: 0x4a / 255, blue: 0x4a / 255)
        let nameColor = Color(red: 0xf5 / 255, green: 0xf0 / 255, blue: 0xe8 / 255)
        return VStack(spacing: 2) {
            Text(greetingPhrase())
                .font(.system(size: timeLabelSize, weight: .semibold, design: .default))
                .textCase(.uppercase)
                .kerning(timeLabelSize * 0.16)
                .foregroundStyle(timeColor)
                .multilineTextAlignment(.center)
            Text(displayName)
                .font(.system(size: nameSize, weight: .bold, design: .serif))
                .kerning(nameSize * -0.03)
                .lineSpacing(nameSize * (0.9 - 1.18))
                .foregroundStyle(nameColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 20)
        .accessibilityAddTraits(.isHeader)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if naplexDate == nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    openNaplexEditor()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.appSecondaryText)
                            .frame(width: 22)

                        Text(String(localized: "Optional: anchor a NAPLEX month on your timeline."))
                            .font(theme.appFont(13))
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(theme.appFont(13, weight: .semibold))
                            .foregroundStyle(Color.appTertiaryText)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .minimumHitTarget()

                Divider()
                    .padding(.vertical, 16)
                    .opacity(colorScheme == .dark ? 0.22 : 0.55)
            }

            tickerCarouselInset
                .padding(.top, naplexDate == nil ? 0 : 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .growthHeroPlate()
    }

    @ViewBuilder
    private var tickerCarouselInset: some View {
        if tickerEntries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    TickerCardGlowBackground(
                        accentColor: tickerCarouselGlowAccentColor,
                        colorScheme: colorScheme
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(-30)
                    .allowsHitTesting(false)
                    .animation(.easeInOut, value: tickerPage)

                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        GrowthTickerUIKitPager(
                            selection: $tickerPage,
                            pageCount: tickerEntries.count,
                            pageWidth: w,
                            pageHeight: 148,
                            layoutKey: tickerPagerLayoutKey(pageWidth: w),
                            pages: AnyView(
                                HStack(spacing: 0) {
                                    ForEach(Array(tickerEntries.enumerated()), id: \.offset) { _, entry in
                                        tickerRow(for: entry)
                                            .frame(width: w, height: 148)
                                    }
                                }
                            )
                        )
                        .frame(height: 148)
                    }
                    .frame(height: 148)
                }

                if tickerEntries.count > 1 {
                    HStack {
                        Spacer(minLength: 0)
                        GrowthTickerDotCapsuleIndicator(
                            pageCount: tickerEntries.count,
                            currentPage: tickerPage
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityHint(String(localized: "Swipe sideways for more reminders."))
        }
    }

    /// `GrowthTickerEntry.id` is stable per slot (e.g. `"streak"`). Without this, SwiftUI often reuses
    /// the same row when only `streak7Day` / footnote change — the pager may not refresh the active slide.
    private func tickerEntryRowIdentity(_ entry: GrowthTickerEntry) -> String {
        "\(entry.id)|streak:\(entry.streak7Day.map(String.init) ?? "-")|q:\(entry.quizPercent.map(String.init) ?? "-")|h:\(entry.headline)|f:\(entry.footnote ?? "")|e:\(entry.examDaysUntil.map(String.init) ?? "-")"
    }

    /// Per-card accent for `TickerCardGlowBackground`. Matches each card's hero color:
    /// streak -> orange (the "days" label), naplex -> blue (date pill), daily.done -> score
    /// brackets matching `QuizDoneTickerCard.scoreColor` (>=80 green, >=60 orange, else red),
    /// daily.open -> white (subtle until we have a brand hue).
    private func tickerGlowAccent(for entry: GrowthTickerEntry) -> Color {
        switch entry.id {
        case "streak":     return .orange
        case "naplex":     return .blue
        case "daily.done":
            guard let pct = entry.quizPercent else { return .green }
            if pct >= 80 { return .green }
            if pct >= 60 { return .orange }
            return .red
        default:           return .white
        }
    }

    /// Accent for the shared carousel glow layer; tracks `tickerPage` so the hue updates on swipe.
    private var tickerCarouselGlowAccentColor: Color {
        let entries = tickerEntries
        guard !entries.isEmpty else { return .white }
        let idx = loopingIndex(tickerPage, count: entries.count)
        return tickerGlowAccent(for: entries[idx])
    }

    /// Drives `GrowthTickerUIKitPager` root refresh when ticker data or width changes.
    private func tickerPagerLayoutKey(pageWidth: CGFloat) -> String {
        let fp = tickerEntries.map { tickerEntryRowIdentity($0) }.joined(separator: "|")
        return "\(fp)@\(Int(pageWidth * 100))"
    }

    private func tickerRow(for entry: GrowthTickerEntry) -> some View {
        Button {
            entry.onTap()
        } label: {
            Group {
                switch entry.id {
                case "streak":
                    StreakTickerCard(
                        entry: entry,
                        colorScheme: colorScheme,
                        celebrationToken: streakFlameCelebrationToken
                    )
                case "naplex":
                    ExamTickerCard(entry: entry, colorScheme: colorScheme)
                case "daily.done":
                    QuizDoneTickerCard(entry: entry, colorScheme: colorScheme)
                default:
                    QuizOpenTickerCard(entry: entry, colorScheme: colorScheme)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(tickerEntryRowIdentity(entry))
        .accessibilityHint(entry.handlesNavigation ? String(localized: "Opens more detail.") : String(localized: "Status update."))
    }

    private var dueForReviewBody: some View {
        Group {
            if !prioritizedDueDrugs.isEmpty {
                dueForReviewSection
            }
        }
    }

    private var sortedDailyArchiveDrugs: [Drug] {
        let dailyDrugs = progress.drugsWithDailyAttempts(from: DrugService.shared.drugs)
        return dailyDrugs.sorted { lhs, rhs in
            let lhsBest = progress.bestDailyScore(for: lhs) ?? 0
            let rhsBest = progress.bestDailyScore(for: rhs) ?? 0
            if lhsBest != rhsBest { return lhsBest > rhsBest }
            return lhs.genericName.localizedCaseInsensitiveCompare(rhs.genericName) == .orderedAscending
        }
    }

    /// Daily-archive drugs other than the Growth carousel “today” assignment (no calendar metadata on attempts).
    private var dailyArchiveDrugsExcludingTodayDrug: [Drug] {
        let todayId = todayDrug?.id
        return sortedDailyArchiveDrugs.filter { $0.id != todayId }
    }

    /// Resolves the collapsed archive row when `lastDailyQuizSession` is missing (e.g. Library launches
    /// use `QuizSource.library`) or legacy installs never persisted the daily session key.
    private var dailyArchiveCompactRowModel: (drug: Drug, detailLine: String)? {
        let catalog = DrugService.shared.drugs
        func resolvedDrug(forDrugId id: String) -> Drug? {
            catalog.first { $0.id == id }
        }
        func sessionSubtitle(_ session: LastDrugQuizSessionSummary) -> String {
            String.localizedStringWithFormat(
                String(localized: "%lld%% • %lld of %lld correct • %@"),
                Int64(session.scorePercent),
                Int64(session.correctCount),
                Int64(session.totalCount),
                relativeSessionLabel(for: Date(timeIntervalSince1970: session.timestamp))
            )
        }

        if let session = progress.lastDailyQuizSession,
           let drug = resolvedDrug(forDrugId: session.drugId) {
            return (drug, sessionSubtitle(session))
        }
        if let session = progress.lastDrugQuizSession,
           let drug = resolvedDrug(forDrugId: session.drugId),
           progress.lastAppendedQuizSource(forDrugId: session.drugId) == .daily {
            return (drug, sessionSubtitle(session))
        }
        if let td = todayDrug,
           let session = progress.lastDrugQuizSession,
           session.drugId == td.id,
           progress.hasAwardedDailyQuizXPToday() {
            return (td, sessionSubtitle(session))
        }
        if let td = todayDrug,
           !progress.scores(for: td, filter: .daily).isEmpty,
           let pct = progress.latestDailyQuizPercent(for: td) {
            let attempts = progress.dailyAttemptCount(for: td)
            let attemptsLabel: String = attempts == 1
                ? String(localized: "1 attempt")
                : String.localizedStringWithFormat(String(localized: "%lld attempts"), Int64(attempts))
            let line = String.localizedStringWithFormat(
                String(localized: "%lld%% • %@"),
                Int64(pct),
                attemptsLabel
            )
            return (td, line)
        }
        if let drug = sortedDailyArchiveDrugs.first,
           let pct = progress.latestDailyQuizPercent(for: drug) {
            let attempts = progress.dailyAttemptCount(for: drug)
            let attemptsLabel: String = attempts == 1
                ? String(localized: "1 attempt")
                : String.localizedStringWithFormat(String(localized: "%lld attempts"), Int64(attempts))
            let line = String.localizedStringWithFormat(
                String(localized: "%lld%% • %@"),
                Int64(pct),
                attemptsLabel
            )
            return (drug, line)
        }
        return nil
    }

    private var dailyArchiveSection: some View {
        List {
            Section {
                if let row = dailyArchiveCompactRowModel {
                    Button {
                        quizCoverItem = GrowthQuizCoverItem(drug: row.drug, source: .daily)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.drug.genericName.capitalized)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryText)
                                Text(row.detailLine)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Replay daily quiz — \(row.drug.genericName.capitalized)"))
                } else {
                    Text(String(localized: "No daily quizzes yet"))
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Daily drug archive"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                    Spacer(minLength: 12)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showDailyArchive = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .symbolRenderingMode(.hierarchical)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(String(localized: "Open daily drug archive")))
                }
                .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 52)
        .sheet(
            isPresented: $showDailyArchive,
            onDismiss: {
                if let drug = pendingDailyArchiveDrug {
                    pendingDailyArchiveDrug = nil
                    quizCoverItem = GrowthQuizCoverItem(drug: drug, source: .daily)
                }
            }
        ) {
            dailyDrugArchiveDrawer
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var dailyDrugArchiveDrawer: some View {
        NavigationStack {
            Group {
                let drugs = sortedDailyArchiveDrugs
                if drugs.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No daily quizzes yet"),
                        systemImage: "calendar.badge.checkmark",
                        description: Text(String(localized: "Complete a daily drug quiz to start your archive."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(drugs) { drug in
                                dailyArchiveListRow(drug)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.appBackground)
            .navigationTitle(String(localized: "Daily drug archive"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        showDailyArchive = false
                    }
                }
            }
        }
    }

    private func dailyArchiveListRow(_ drug: Drug) -> some View {
        let best = progress.bestDailyScore(for: drug) ?? 0
        let attempts = progress.dailyAttemptCount(for: drug)
        let badgeColor: Color = {
            if best >= 80 { return .green }
            if best >= 50 { return .orange }
            return .red
        }()
        let attemptsLabel: String = {
            if attempts == 1 {
                return String(localized: "1 attempt")
            }
            return String.localizedStringWithFormat(
                String(localized: "%lld attempts"),
                Int64(attempts)
            )
        }()

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pendingDailyArchiveDrug = drug
            showDailyArchive = false
        } label: {
            LabeledContent {
                Text("\(best)%")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(badgeColor)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(drug.genericName.capitalized)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryText)
                    Text(attemptsLabel)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Replay daily quiz — \(drug.genericName.capitalized), best \(best) percent"))
    }

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(progress.totalXP) XP")
                    .font(theme.appFont(32, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)

                Text(String(localized: "Total"))
                    .font(theme.appFont(11))
                    .foregroundStyle(Color.appTertiaryText)
            }

            Divider()
                .opacity(colorScheme == .dark ? 0.22 : 0.55)

            rankProgressBarBlock(animatedFill: xpBarShownRatio)

            Divider()
                .opacity(colorScheme == .dark ? 0.22 : 0.55)

            weeklyResultsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .growthSecondaryCard()
        .sheet(isPresented: $showWeeklyResults) {
            WeeklyResultsDrawerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var weeklyResultsRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showWeeklyResults = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 22)

                Text(String(localized: "Weekly results"))
                    .font(theme.appFont(14, weight: .medium))
                    .foregroundStyle(Color.appPrimaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(theme.appFont(13, weight: .semibold))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(Text(String(localized: "Open weekly results")))
    }

    private var dailyAttemptHistorySection: some View {
        let otherDrugs = dailyArchiveDrugsExcludingTodayDrug
        let todayAttemptRows: [(label: String, percent: Int)] = {
            guard let td = todayDrug else { return [] }
            return dailyQuizAttemptHistoryRows(for: td)
        }()

        return VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Archives"))
                .font(theme.appFont(15, weight: .semibold))
                .foregroundStyle(Color.appPrimaryText)
                .accessibilityAddTraits(.isHeader)

            if let td = todayDrug {
                Text(td.genericName.capitalized)
                    .font(theme.appFont(14, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .accessibilityLabel(
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "Today's drug, %@"),
                                td.genericName.capitalized
                            )
                        )
                    )

                if todayAttemptRows.isEmpty {
                    Text(String(localized: "No daily attempts yet for today's drug."))
                        .font(theme.appFont(13))
                        .foregroundStyle(Color.appSecondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(todayAttemptRows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label)
                                    .font(theme.appFont(13, weight: .medium))
                                    .foregroundStyle(Color.appTertiaryText)
                                Spacer(minLength: 12)
                                Text("\(row.percent)%")
                                    .font(.system(size: 17, weight: .semibold, design: .serif))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.appPrimaryText)
                            }
                            .accessibilityLabel(
                                Text(
                                    String.localizedStringWithFormat(
                                        String(localized: "%@, %lld percent"),
                                        row.label,
                                        Int64(row.percent)
                                    )
                                )
                            )
                        }
                    }
                }
            }

            if !otherDrugs.isEmpty {
                if todayDrug != nil {
                    Divider()
                        .opacity(colorScheme == .dark ? 0.22 : 0.55)
                }

                Text(String(localized: "Other drugs with daily attempts"))
                    .font(theme.appFont(12, weight: .semibold))
                    .foregroundStyle(Color.appTertiaryText)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(otherDrugs) { drug in
                        let best = progress.bestDailyScore(for: drug) ?? 0
                        let avg = progress.averageScore(for: drug, filter: .daily)
                        HStack(alignment: .top, spacing: 10) {
                            Text(drug.genericName.capitalized)
                                .font(theme.appFont(15, weight: .semibold))
                                .foregroundStyle(Color.appPrimaryText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(
                                    String.localizedStringWithFormat(
                                        String(localized: "Best %lld%%"),
                                        Int64(best)
                                    )
                                )
                                .font(theme.appFont(13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(archiveDailyGradeColor(best))
                                Text(
                                    String.localizedStringWithFormat(
                                        String(localized: "Avg %lld%%"),
                                        Int64(avg)
                                    )
                                )
                                .font(theme.appFont(13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(archiveDailyGradeColor(avg))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String.localizedStringWithFormat(
                                String(localized: "%@, best %lld percent, average %lld percent"),
                                drug.genericName.capitalized,
                                Int64(best),
                                Int64(avg)
                            )
                        )
                    }
                }
            }

            if todayDrug == nil && otherDrugs.isEmpty {
                Text(String(localized: "Complete a daily drug quiz to see attempt history here."))
                    .font(theme.appFont(13))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .growthSecondaryCard()
    }

    private func archiveDailyGradeColor(_ percent: Int) -> Color {
        if percent >= 80 { return .green }
        if percent >= 50 { return .orange }
        return .red
    }

    /// Ordinals for daily-attempt rows (matches `QuizView` quiz results copy).
    private func growthOrdinalAttemptLabel(_ n: Int) -> String {
        let rem100 = n % 100
        if (11...13).contains(rem100) {
            return "\(n)th"
        }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// Up to the last three `.daily`-source scores for this drug with `1st att`-style labels (indices in the daily-only list).
    private func dailyQuizAttemptHistoryRows(for drug: Drug) -> [(label: String, percent: Int)] {
        let full = progress.scores(for: drug, filter: .daily)
        let count = full.count
        guard count > 0 else { return [] }
        let shown = min(3, count)
        let start = count - shown
        return (0..<shown).map { offset in
            let index = start + offset
            let attemptNumber = index + 1
            return (growthOrdinalAttemptLabel(attemptNumber) + " att", full[index])
        }
    }

    private func rankProgressFillRatio(for info: (currentXP: Int, currentMin: Int, nextMin: Int, nextRankTitle: String, isMaxRank: Bool)) -> CGFloat {
        if info.isMaxRank { return 1.0 }
        let span = CGFloat(info.nextMin - info.currentMin)
        guard span > 0 else { return 1.0 }
        let progressValue = CGFloat(info.currentXP - info.currentMin)
        let ratio = progressValue / span
        return min(max(ratio, 0), 1)
    }

    private func rankProgressBarTrack(fillRatio: CGFloat, reveal: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * fillRatio * reveal
            let minimum: CGFloat = fillRatio > 0 && reveal > 0 ? 2 : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appInputBackground)
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 14/255,  green: 165/255, blue: 233/255), location: 0.0),
                                .init(color: Color(red: 186/255, green: 230/255, blue: 253/255), location: 0.5),
                                .init(color: Color(red: 244/255, green: 114/255, blue: 182/255), location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().frame(width: max(width, minimum))
                            Spacer(minLength: 0)
                        }
                    )
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.9), value: reveal)
    }

    @ViewBuilder
    private func rankProgressBarBlock(animatedFill: CGFloat) -> some View {
        let info = progress.rankProgressInfo
        let fillRatio = rankProgressFillRatio(for: info)

        VStack(alignment: .leading, spacing: 6) {
            rankProgressBarTrack(fillRatio: fillRatio, reveal: animatedFill)

            if info.isMaxRank {
                Text("You're at the top tier.")
                    .font(theme.appFont(13))
                    .foregroundStyle(Color.appTertiaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                HStack {
                    Text("\(info.currentXP) / \(info.nextMin) XP")
                        .font(theme.appFont(12))
                        .foregroundStyle(Color.appTertiaryText)
                    Spacer()
                    Text(info.nextRankTitle)
                        .font(theme.appFont(12))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
        }
    }


    private var dueForReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Due for review"))
                .font(theme.appFont(15, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)

            VStack(spacing: 10) {
                ForEach(prioritizedDueDrugs) { drug in
                    Button {
                        quizCoverItem = GrowthQuizCoverItem(drug: drug, source: .daily)
                    } label: {
                        drugRow(drug, showMasteredBadge: false, neutralBadge: true)
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .growthSecondaryCard()
    }

    private func drugRow(_ drug: Drug, showMasteredBadge: Bool, neutralBadge: Bool = false) -> some View {
        let score = progress.averageScore(for: drug)
        let badgeColor: Color = {
            if score >= 80 { return .green }
            if score >= 50 { return .orange }
            return .red
        }()

        let baseRow = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(drug.genericName.capitalized)
                    .font(theme.appFont(16, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
                Text(drug.drugClass)
                    .font(theme.appFont(13))
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer()

            if showMasteredBadge && progress.isMastered(drug) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            Text("\(score)%")
                .font(theme.appFont(12, weight: .semibold))
                .foregroundStyle(neutralBadge ? Color.appSecondaryText : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(neutralBadge ? Color.appInputBackground.opacity(0.8) : badgeColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)

        return AnyView(baseRow.growthGroupedDrugWell())
    }

    // MARK: - Behaviors + utilities

    private func hydrateXpBarRatio(animated: Bool) {
        if accessibilityReduceMotion || !animated {
            xpBarShownRatio = 1
            return
        }
        xpBarShownRatio = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.95)) {
                xpBarShownRatio = 1
            }
        }
    }

    /// Keeps `tickerPage` in range when slides are added/removed; the ticker only advances via user swipe.
    private func syncTickerPageWithEntryCount() {
        let count = tickerEntries.count
        if count <= 1 {
            tickerPage = 0
        } else if tickerPage >= count {
            tickerPage = max(count - 1, 0)
        }
    }

    private func openNaplexEditor() {
        editDate = naplexDate ?? Date()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showNaplexEdit = true
        }
    }

    private var naplexEditOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissNaplexEditor()
                }

            VStack(spacing: 20) {
                HStack {
                    Button {
                        dismissNaplexEditor()
                    } label: {
                        Image(systemName: "xmark")
                            .font(theme.appFont(15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appInputBackground)
                            .clipShape(Circle())
                    }
                    .minimumHitTarget()
                    Spacer()
                    Text(String(localized: "NAPLEX Date"))
                        .font(theme.appFont(16, weight: .semibold))
                    Spacer()
                    Button {
                        UserDefaults.standard.removeObject(forKey: "naplexDate")
                        UserProgressService.shared.syncProfileOnly()
                        dismissNaplexEditor()
                    } label: {
                        Text(String(localized: "Clear"))
                            .font(theme.appFont(14))
                            .foregroundStyle(.red)
                    }
                    .minimumHitTarget()
                }

                DatePicker(
                    "",
                    selection: $editDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button {
                    UserDefaults.standard.set(editDate.timeIntervalSince1970, forKey: "naplexDate")
                    UserProgressService.shared.syncProfileOnly()
                    dismissNaplexEditor()
                } label: {
                    Text(String(localized: "Save"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.black)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.2), value: showNaplexEdit)
    }

    private func dismissNaplexEditor() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showNaplexEdit = false
        }
    }
}

#Preview {
    ProgressDashboardView()
}

extension Notification.Name {
    static let switchToTodayTab = Notification.Name("switchToTodayTab")
    static let switchToLibraryTab = Notification.Name("switchToLibraryTab")
}
