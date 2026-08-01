import SwiftUI
import UIKit

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

// TODO(tech-debt): The question-card markup below is a DELIBERATE third copy of the
// quiz card, alongside `QuizView.questionCard` and `ClassQuizView.questionCard`.
// Consolidating all three into a shared `QuizQuestionCardView` is deferred tech debt
// and was intentionally NOT done during onboarding activation. This screen reuses the
// `QuizQuestion` model only — it does not introduce a new quiz engine.
struct WelcomeChallengeStepView: View {
    @ObservedObject var vm: OnboardingViewModel

    private let items = OnboardingChallenge.items

    @State private var currentIndex = 0
    @State private var selectedAnswer: String?
    @State private var hasSubmitted = false
    @State private var correctCount = 0
    @State private var misses: [OnboardingMiss] = []

    private var currentItem: OnboardingChallenge.Item { items[currentIndex] }
    private var currentQuestion: QuizQuestion { currentItem.question }
    private var isLastQuestion: Bool { currentIndex == items.count - 1 }

    private var selectedIsCorrect: Bool {
        guard let selectedAnswer else { return false }
        return currentQuestion.correctAnswers.contains(selectedAnswer)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)

            ScrollView {
                questionCard
                    .id(currentQuestion.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            bottomButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header (welcome line + question progress)

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            progressSegments
            Text("Welcome to MemoRx \u{2014} let\u{2019}s see where you\u{2019}re at")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressSegments: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx <= currentIndex ? warmGold : Color.appSecondaryText.opacity(0.18))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Question card (deliberate third copy — see TODO above)

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QUESTION \(currentIndex + 1) OF \(items.count)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 16)

            Text(currentQuestion.question)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(.label))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 24)

            VStack(spacing: 10) {
                ForEach(currentQuestion.options, id: \.self) { option in
                    optionButton(option)
                }
            }

            if hasSubmitted, !currentQuestion.explanation.isEmpty {
                Spacer().frame(height: 14)
                explanationBox
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(24)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func optionButton(_ option: String) -> some View {
        let isSelected = selectedAnswer == option
        let isCorrectOption = currentQuestion.correctAnswers.contains(option)
        let showCorrectReveal = hasSubmitted && isCorrectOption
        let isWrongReveal = hasSubmitted && isSelected && !isCorrectOption

        let backgroundColor: Color = {
            if showCorrectReveal { return Color.green.opacity(0.15) }
            if isWrongReveal { return Color.red.opacity(0.12) }
            return Color.appCardBackground
        }()
        let borderColor: Color = {
            if showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return isSelected ? Color(.label) : Color(.tertiarySystemFill)
        }()
        let textColor: Color = {
            if showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return .primary
        }()
        let iconName: String = {
            if showCorrectReveal { return "checkmark.circle.fill" }
            if isWrongReveal { return "xmark.circle.fill" }
            return isSelected ? "largecircle.fill.circle" : "circle"
        }()
        let iconColor: Color = {
            if showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return isSelected ? Color(.label) : .gray
        }()

        return Button {
            guard !hasSubmitted else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedAnswer = isSelected ? nil : option
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
                Text(option)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: borderColor == Color(.tertiarySystemFill) ? 1 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var explanationBox: some View {
        Text(currentQuestion.explanation)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedIsCorrect ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Bottom action (Submit → Next/See results)

    @ViewBuilder
    private var bottomButton: some View {
        if hasSubmitted {
            primaryActionButton(
                title: isLastQuestion ? "See your results" : "Next Question \u{2192}",
                enabled: true
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if isLastQuestion {
                    // Hand the score + missed drugs to the result screen, then advance.
                    vm.challengeCorrect = correctCount
                    vm.challengeMisses = misses
                    vm.advance()
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        currentIndex += 1
                        selectedAnswer = nil
                        hasSubmitted = false
                    }
                }
            }
        } else {
            primaryActionButton(title: "Submit Answer", enabled: selectedAnswer != nil) {
                guard selectedAnswer != nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    hasSubmitted = true
                }
                if selectedIsCorrect {
                    correctCount += 1
                } else {
                    misses.append(OnboardingMiss(
                        drugGenericName: currentItem.drugGenericName,
                        missedAnswer: currentQuestion.correctAnswers.first ?? ""
                    ))
                }
                let style: UIImpactFeedbackGenerator.FeedbackStyle = selectedIsCorrect ? .heavy : .rigid
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        }
    }

    private func primaryActionButton(
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(enabled ? Color(.label) : Color(.tertiarySystemFill))
                .foregroundStyle(enabled ? Color(.systemBackground) : Color(.secondaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
