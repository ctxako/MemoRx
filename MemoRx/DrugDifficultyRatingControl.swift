import SwiftUI
import UIKit

/// Four-segment difficulty control. `nil` = unrated (no thumb) until the user picks 1…4.
struct DrugDifficultyRatingControl: View {
    @Binding var level: Int?
    @Environment(\.colorScheme) private var colorScheme

    private static let segmentCount = 4
    private static let controlWidth: CGFloat = 152
    private static let rowHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let totalW = geo.size.width
                let segW = totalW / CGFloat(Self.segmentCount)
                let thumbInset: CGFloat = 3
                let thumbW = segW - thumbInset * 2
                let thumbH = Self.rowHeight - thumbInset * 2
                let thumbX: CGFloat = {
                    guard let lv = level else { return thumbInset }
                    return thumbInset + CGFloat(lv - 1) * segW
                }()

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(trackFill)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(trackStroke, lineWidth: 1)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(thumbFill)
                        .shadow(
                            color: colorScheme == .dark
                                ? Color.black.opacity(0.45)
                                : Color.black.opacity(0.12),
                            radius: colorScheme == .dark ? 5 : 3,
                            x: 0,
                            y: 1
                        )
                        .frame(width: thumbW, height: thumbH)
                        .offset(x: thumbX, y: thumbInset)
                        .opacity(level == nil ? 0 : 1)
                        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: level)

                    HStack(spacing: 0) {
                        ForEach(1...Self.segmentCount, id: \.self) { i in
                            segmentLabel(index: i, width: segW)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            applyLocation(x: value.location.x, totalWidth: totalW)
                        }
                )
            }
            .frame(width: Self.controlWidth, height: Self.rowHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Difficulty")
            .accessibilityValue(Self.tierLabel(level))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    bump(1)
                case .decrement:
                    bump(-1)
                @unknown default:
                    break
                }
            }

            Text(Self.tierLabel(level))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(captionColor)
                .multilineTextAlignment(.center)
                .frame(width: Self.controlWidth)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: level)
        }
    }

    private func segmentLabel(index: Int, width: CGFloat) -> some View {
        let selected = level == index
        return Text("\(index)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? thumbLabelColor : normalForeground)
            .frame(width: width, height: Self.rowHeight)
            .animation(.easeInOut(duration: 0.18), value: level)
    }

    private var thumbFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.88)
    }

    private var thumbLabelColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private func applyLocation(x: CGFloat, totalWidth: CGFloat) {
        let w = totalWidth / CGFloat(Self.segmentCount)
        let idx = Int(x / w)
        let clamped = min(max(idx, 0), Self.segmentCount - 1) + 1
        setLevel(clamped)
    }

    private func bump(_ delta: Int) {
        if delta > 0 {
            switch level {
            case nil:
                setLevel(1)
            case let l? where l < Self.segmentCount:
                setLevel(l + 1)
            default:
                break
            }
        } else {
            switch level {
            case nil:
                break
            case 1?:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                level = nil
            case let l? where l > 1:
                setLevel(l - 1)
            default:
                break
            }
        }
    }

    private func setLevel(_ newLevel: Int) {
        let v = min(max(newLevel, 1), Self.segmentCount)
        guard v != level else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        level = v
    }

    private var trackFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    private var trackStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.1)
    }

    private var normalForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.52)
            : Color.black.opacity(0.42)
    }

    private var captionColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.62)
            : Color.black.opacity(0.5)
    }

    static func tierLabel(_ level: Int?) -> String {
        guard let level else { return "Unrated" }
        switch level {
        case 1: return "Weak · revisit"
        case 2: return "Shaky"
        case 3: return "Solid"
        case 4: return "Mastered"
        default: return "Unrated"
        }
    }
}
