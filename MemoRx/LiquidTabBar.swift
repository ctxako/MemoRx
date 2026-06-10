import SwiftUI
import UIKit

// MARK: - Tab geometry

private struct TabCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - LiquidCapsule

/// A capsule whose horizontal center and width participate in SwiftUI’s shape animation —
/// the path interpolates between frames so motion reads as a morphing blob, not a cross-fade.
struct LiquidCapsule: Shape {
    var centerX: CGFloat
    var width: CGFloat
    var height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(centerX, width) }
        set {
            centerX = newValue.first
            width = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = max(width, height * 1.1)
        let h = height
        let x = centerX - w * 0.5
        let y = rect.midY - h * 0.5
        return Capsule(style: .continuous).path(in: CGRect(x: x, y: y, width: w, height: h))
    }
}

// MARK: - LiquidTabBar

/// Custom tab bar with a glass capsule highlight and liquid-style stretch between tabs.
struct LiquidTabBar: View {
    let symbols: [String]
    @Binding var selectedIndex: Int
    var accessibilityLabels: [String]? = nil

    @Environment(\.colorScheme) private var colorScheme

    @State private var highlightCenter: CGFloat = 0
    @State private var highlightWidth: CGFloat = 64
    @State private var overshootExtra: CGFloat = 0
    @State private var didBindInitialHighlight = false
    /// Measured tab icon centers in `liquidTabBar` space (from `PreferenceKey`).
    @State private var measuredCenters: [CGFloat] = []

    private let capsuleHeight: CGFloat = 40
    private let iconPointSize: CGFloat = 22
    private let iconWeight: Font.Weight = .bold
    /// Horizontal padding from icon to capsule edge (each side).
    private let capsuleHorizontalPadding: CGFloat = 16
    /// One curve for center, width, and overshoot. Lower response + moderate damping = snappy without feeling mushy.
    private let highlightSpring = Animation.spring(response: 0.28, dampingFraction: 0.73)
    @State private var feedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let count = max(symbols.count, 1)
            let cellWidth = geo.size.width / CGFloat(count)
            let fallbackCenters = (0..<count).map { (CGFloat($0) + 0.5) * cellWidth }
            let centers: [CGFloat] = measuredCenters.count == count ? measuredCenters : fallbackCenters
            let iconColumnWidth: CGFloat = iconPointSize + 4
            let targetWidth = min(
                max(iconColumnWidth + capsuleHorizontalPadding * 2, 52),
                min(cellWidth * 0.78, 88)
            )

            ZStack {
                // Highlight layer
                let displayWidth = highlightWidth + overshootExtra
                let stretchRatio = min(overshootExtra / max(highlightWidth, 1), 0.45)

                highlightCapsule(displayWidth: displayWidth, stretchRatio: stretchRatio)
                    .opacity(didBindInitialHighlight ? 1 : 0)

                HStack(spacing: 0) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, systemName in
                        Button {
                            selectTab(
                                index: index,
                                centers: centers,
                                targetWidth: targetWidth
                            )
                        } label: {
                            Image(systemName: systemName)
                                .font(.system(size: iconPointSize, weight: iconWeight))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(iconColor(selected: index == selectedIndex))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(capsuleHeight + 12, 52))
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(accessibilityLabel(for: index))
                        .buttonStyle(.plain)
                        .minimumHitTarget()
                        .background(
                            GeometryReader { itemGeo in
                                Color.clear.preference(
                                    key: TabCenterPreferenceKey.self,
                                    value: [index: itemGeo.frame(in: .named("liquidTabBar")).midX]
                                )
                            }
                        )
                    }
                }
                .coordinateSpace(name: "liquidTabBar")
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onPreferenceChange(TabCenterPreferenceKey.self) { pairs in
                let sorted = (0..<count).compactMap { pairs[$0] }
                guard sorted.count == count else { return }
                measuredCenters = sorted
                guard !didBindInitialHighlight else { return }
                guard selectedIndex >= 0, selectedIndex < sorted.count else { return }
                let expectedCenter = sorted[selectedIndex]
                var tr = Transaction()
                tr.animation = nil
                withTransaction(tr) {
                    highlightCenter = expectedCenter
                    highlightWidth = targetWidth
                }
                didBindInitialHighlight = true
            }
            .onChange(of: geo.size.width) { _, _ in
                let c = measuredCenters.count == count ? measuredCenters : fallbackCenters
                guard didBindInitialHighlight, selectedIndex < c.count else { return }
                var tr = Transaction()
                tr.animation = nil
                withTransaction(tr) {
                    highlightCenter = c[selectedIndex]
                    highlightWidth = targetWidth
                }
            }
            .onChange(of: selectedIndex) { _, new in
                guard didBindInitialHighlight, new >= 0, new < centers.count else { return }
                let expected = centers[new]
                // Sync when `selectedIndex` changes without a local tap (e.g. binding).
                if abs(highlightCenter - expected) > 2 {
                    withAnimation(highlightSpring) {
                        highlightCenter = expected
                        highlightWidth = targetWidth
                        overshootExtra = 0
                    }
                }
            }
        }
        .frame(height: 56)
        .accessibilityElement(children: .contain)
        .onAppear {
            feedback.prepare()
        }
    }

    @ViewBuilder
    private func highlightCapsule(displayWidth: CGFloat, stretchRatio: CGFloat) -> some View {
        let shape = LiquidCapsule(
            centerX: highlightCenter,
            width: displayWidth,
            height: capsuleHeight
        )
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }
            // Gentler distortion = fewer transform conflicts with the morphing path on each frame.
            .scaleEffect(
                x: 1.0 + stretchRatio * 0.08,
                y: 1.0 - stretchRatio * 0.04,
                anchor: UnitPoint(x: 0.5, y: 0.5)
            )
            .compositingGroup()
    }

    private func iconColor(selected: Bool) -> Color {
        if selected {
            return colorScheme == .dark ? .white : .black
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.58)
            : Color.black.opacity(0.58)
    }

    private func selectTab(index: Int, centers: [CGFloat], targetWidth: CGFloat) {
        guard index != selectedIndex, index < centers.count, index >= 0 else { return }

        let toCenter = centers[index]
        let travel = abs(toCenter - highlightCenter)
        // Slightly more stretch on a fast spring so the “liquid” read still lands in fewer frames.
        let peakOvershoot = min(travel * 0.28, 40)

        feedback.impactOccurred()
        feedback.prepare()

        // Bump width before the spring so the same curve handles travel + stretch decay (smoother than two springs).
        overshootExtra = peakOvershoot

        withAnimation(highlightSpring) {
            selectedIndex = index
            highlightCenter = toCenter
            highlightWidth = targetWidth
            overshootExtra = 0
        }
    }

    private func accessibilityLabel(for index: Int) -> String {
        guard let accessibilityLabels, index >= 0, index < accessibilityLabels.count else {
            return "Tab \(index + 1)"
        }
        return accessibilityLabels[index]
    }
}

// MARK: - Preview

#Preview("Liquid tab bar") {
    struct PreviewHost: View {
        @State private var tab = 1
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                    LiquidTabBar(
                        symbols: ["sun.max.fill", "books.vertical.fill", "chart.bar.fill"],
                        selectedIndex: $tab
                    )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                }
            }
        }
    }
    return PreviewHost()
}
