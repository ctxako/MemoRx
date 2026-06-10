import SwiftUI
import UIKit

// MARK: - Windowing

private enum DrugProgressWindow {
    /// Sliding window of at most `maxVisible` indices centered on `currentIndex` (±3 for 7), clamped at ends.
    static func visibleRange(itemCount: Int, currentIndex: Int, maxVisible: Int = 7) -> Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let size = min(maxVisible, itemCount)
        var start = currentIndex - maxVisible / 2
        start = max(0, start)
        start = min(start, itemCount - size)
        return start..<(start + size)
    }

    /// `true` at indices that start a new class segment in the flat ordered list.
    static func isFirstInClass(_ items: [Drug]) -> [Bool] {
        guard !items.isEmpty else { return [] }
        var flags = Array(repeating: false, count: items.count)
        flags[0] = true
        for i in 1..<items.count {
            flags[i] = items[i].classId != items[i - 1].classId
        }
        return flags
    }
}

// MARK: - Haptics

/// Single light impact generator: prepare on expand, tick on index change, tick on release from expanded session.
private final class DrugProgressIndicatorHaptics {
    private let impact = UIImpactFeedbackGenerator(style: .light)

    func onExpandStart() {
        impact.prepare()
        impact.impactOccurred()
    }

    func onStepChanged(from oldIndex: Int, to newIndex: Int) {
        guard newIndex != oldIndex else { return }
        impact.impactOccurred()
    }

    func onExpandEnd() {
        impact.impactOccurred()
    }
}

// MARK: - Metrics

private struct IndicatorMetrics {
    let dotSpacing: CGFloat
    let capsuleHPadding: CGFloat
    let capsuleVPadding: CGFloat
    let smallDot: CGFloat
    let largeDot: CGFloat

    static func collapsed() -> IndicatorMetrics {
        IndicatorMetrics(dotSpacing: 7, capsuleHPadding: 11, capsuleVPadding: 6, smallDot: 6, largeDot: 10)
    }

    static func expanded() -> IndicatorMetrics {
        IndicatorMetrics(dotSpacing: 10, capsuleHPadding: 14, capsuleVPadding: 10, smallDot: 8, largeDot: 13)
    }
}

// MARK: - Component

/// Horizontal capsule of dots for library position.
/// - Tap a visible dot to jump directly.
/// - Swipe left/right for quick adjacent navigation.
/// - Long-press (~0.15s) then drag for precise multi-step scrubbing (~25pt per index).
struct DrugProgressIndicator: View {
    let items: [Drug]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    private let maxVisibleDots = 7
    private let expandHoldDuration: TimeInterval = 0.15
    private let pixelsPerStep: CGFloat = 25
    private let swipeStepDistance: CGFloat = 22
    private let swipeDirectionalBias: CGFloat = 1.2
    private let tapMaxDistance: CGFloat = 14
    private let tapMaxDuration: TimeInterval = 0.35

    @State private var expanded = false
    @State private var touchBeganAt: Date?
    @State private var verticalIntent = false
    @State private var enteredExpandedThisTouch = false
    @State private var expansionWidthAnchor: CGFloat = 0
    @State private var lastEffectiveWidth: CGFloat = 0
    @State private var stepRemainder: CGFloat = 0
    @State private var fingerInsideBounds = true
    @State private var capsuleSize: CGSize = .zero
    /// Highlights active dot immediately during step-drag before parent re-renders.
    @State private var interactionIndex: Int?
    @State private var haptics = DrugProgressIndicatorHaptics()

    private var safeIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(currentIndex, 0), items.count - 1)
    }

    private var activeIndex: Int {
        interactionIndex ?? safeIndex
    }

    private var visibleRange: Range<Int> {
        DrugProgressWindow.visibleRange(itemCount: items.count, currentIndex: activeIndex, maxVisible: maxVisibleDots)
    }

    private var firstInClass: [Bool] {
        DrugProgressWindow.isFirstInClass(items)
    }

    private var animationSignature: String {
        let r = visibleRange
        return "\(r.lowerBound)-\(r.upperBound)-\(activeIndex)"
    }

    private var metrics: IndicatorMetrics {
        expanded ? .expanded() : .collapsed()
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                indicatorContent
            }
        }
    }

    private var indicatorContent: some View {
        let range = visibleRange
        let m = metrics
        return HStack(spacing: m.dotSpacing) {
            ForEach(Array(range), id: \.self) { index in
                dotView(at: index, metrics: m)
                    .transition(
                        .scale(scale: 0.65, anchor: .center)
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: animationSignature)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
        .padding(.horizontal, m.capsuleHPadding)
        .padding(.vertical, m.capsuleVPadding)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .preference(key: CapsuleSizeKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(CapsuleSizeKey.self) { capsuleSize = $0 }
        .contentShape(Capsule())
        .gesture(mainDragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Swipe left or right to change drugs. Tap a dot to jump, or long press then drag for precise control.")
    }

    private func dotView(at index: Int, metrics m: IndicatorMetrics) -> some View {
        let isActive = index == activeIndex
        let isClassStart = index < firstInClass.count && firstInClass[index]
        let base = isClassStart ? m.largeDot : m.smallDot
        let diameter = isActive ? base * 1.28 : base

        return Circle()
            .fill(dotFill(isActive: isActive))
            .frame(width: diameter, height: diameter)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isActive)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: diameter)
            .accessibilityLabel(accessibilityTitle(at: index))
    }

    private var mainDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if touchBeganAt == nil {
            touchBeganAt = Date()
            verticalIntent = false
        }

        if !enteredExpandedThisTouch {
            let th = abs(value.translation.height)
            let tw = abs(value.translation.width)
            if th > tw + 10 && th > 18 {
                verticalIntent = true
            }
        }

        let boundsReady = capsuleSize.width > 1 && capsuleSize.height > 1
        let inside = !boundsReady || CGRect(origin: .zero, size: capsuleSize).contains(value.location)

        if inside != fingerInsideBounds {
            if inside {
                lastEffectiveWidth = value.translation.width - expansionWidthAnchor
            }
            fingerInsideBounds = inside
        }

        if !enteredExpandedThisTouch && !verticalIntent, let start = touchBeganAt {
            if Date().timeIntervalSince(start) >= expandHoldDuration {
                enteredExpandedThisTouch = true
                expansionWidthAnchor = value.translation.width
                lastEffectiveWidth = 0
                stepRemainder = 0
                interactionIndex = safeIndex
                haptics.onExpandStart()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    expanded = true
                }
            }
        }

        guard enteredExpandedThisTouch, fingerInsideBounds else { return }

        if abs(value.translation.height) > abs(value.translation.width) * 1.25 {
            return
        }

        let rel = value.translation.width - expansionWidthAnchor
        let delta = rel - lastEffectiveWidth
        lastEffectiveWidth = rel

        stepRemainder += delta

        var idx = interactionIndex ?? safeIndex
        while stepRemainder >= pixelsPerStep {
            let next = min(idx + 1, items.count - 1)
            guard next != idx else {
                stepRemainder = 0
                break
            }
            haptics.onStepChanged(from: idx, to: next)
            idx = next
            interactionIndex = next
            onSelect(next)
            stepRemainder -= pixelsPerStep
        }
        while stepRemainder <= -pixelsPerStep {
            let next = max(idx - 1, 0)
            guard next != idx else {
                stepRemainder = 0
                break
            }
            haptics.onStepChanged(from: idx, to: next)
            idx = next
            interactionIndex = next
            onSelect(next)
            stepRemainder += pixelsPerStep
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let wasExpandedSession = enteredExpandedThisTouch

        if wasExpandedSession {
            haptics.onExpandEnd()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                expanded = false
            }
            resetTouchState()
            return
        }

        defer { resetTouchState() }

        guard !verticalIntent, let start = touchBeganAt else { return }
        let duration = Date().timeIntervalSince(start)
        let horizontal = value.translation.width
        let vertical = value.translation.height
        let dist = hypot(value.translation.width, value.translation.height)

        // Quick swipe mode: no hold required, move one adjacent drug.
        if abs(horizontal) >= swipeStepDistance,
           abs(horizontal) > abs(vertical) * swipeDirectionalBias {
            let direction = horizontal > 0 ? 1 : -1
            let target = min(max(safeIndex + direction, 0), items.count - 1)
            if target != safeIndex {
                haptics.onStepChanged(from: safeIndex, to: target)
                onSelect(target)
            }
            return
        }

        guard duration < tapMaxDuration, dist < tapMaxDistance else { return }

        let x = value.startLocation.x
        let w = max(capsuleSize.width, 1)
        let range = DrugProgressWindow.visibleRange(itemCount: items.count, currentIndex: safeIndex, maxVisible: maxVisibleDots)
        let idx = tapIndex(x: x, capsuleWidth: w, range: range)
        guard items.indices.contains(idx) else { return }
        onSelect(idx)
    }

    private func resetTouchState() {
        touchBeganAt = nil
        verticalIntent = false
        enteredExpandedThisTouch = false
        expansionWidthAnchor = 0
        lastEffectiveWidth = 0
        stepRemainder = 0
        fingerInsideBounds = true
        interactionIndex = nil
    }

    private func tapIndex(x: CGFloat, capsuleWidth: CGFloat, range: Range<Int>) -> Int {
        let n = range.count
        guard n > 0 else { return safeIndex }
        let t = x / capsuleWidth
        let slot = Int((t * CGFloat(n)).rounded(.down))
        let clamped = min(max(slot, 0), n - 1)
        return range.lowerBound + clamped
    }

    private func dotFill(isActive: Bool) -> Color {
        if isActive {
            return Color(.label)
        }
        return Color(.tertiaryLabel).opacity(0.45)
    }

    private func accessibilityTitle(at index: Int) -> String {
        let name = items.indices.contains(index) ? items[index].genericName : "Drug"
        return "Drug \(index + 1) of \(items.count), \(name)"
    }
}

private struct CapsuleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
