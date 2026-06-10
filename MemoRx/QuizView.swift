import SwiftUI
import UIKit

// MARK: - Quiz complete / paywall-aligned presentation

private enum QuizCompleteTheme {
    static let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)
    static let goldBorder = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255).opacity(0.22)
    static let cardCorner: CGFloat = 14
    /// ~2.5× the prior compact summary card body height (~115pt).
    static let summaryCardMinHeight: CGFloat = 288
    static let cardStroke = Color.appSecondaryText.opacity(0.12)
    static let ringEase = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 1.1)
}

struct QuizView: View {
    @Environment(\.appTheme) private var theme
    let drug: Drug
    var source: UserProgressService.QuizSource = .library
    @ObservedObject private var progress = UserProgressService.shared
    @ObservedObject private var dailyChallenge = DailyChallengeService.shared

    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex: Int = 0
    @State private var selectedAnswers: Set<String> = []
    @State private var hasSubmitted: Bool = false
    @State private var correctCount: Int = 0
    @State private var showResults: Bool = false
    @State private var finalizeErrorMessage: String?
    @State private var isFinalizing: Bool = false
    @State private var milestoneBonusXp: Int = 0
    @State private var milestoneDayLabel: Int?
    @State private var milestoneBadgeVisible: Bool = false
    @State private var resultsAnimToken = UUID()
    @State private var resultsHeaderVisible = false
    @State private var resultsRingProgress: CGFloat = 0
    @State private var resultsXPBadgeVisible = false
    @State private var resultsXPBadgeScale: CGFloat = 0.6
    @State private var resultsCardVisible = false
    @State private var resultsButtonsVisible = false
    @Environment(\.dismiss) private var dismiss

    private var currentQuestion: QuizQuestion {
        questions[currentIndex]
    }

    private var selectedIsCorrect: Bool {
        normalizedSet(selectedAnswers) == normalizedSet(Set(currentQuestion.correctAnswers))
    }

    private var canSubmitCurrentQuestion: Bool {
        if currentQuestion.isMultiSelect {
            return selectedAnswers.count == 2
        }
        return selectedAnswers.count == 1
    }

    private var xpEarned: Int {
        progress.calculateQuizXP(correct: correctCount, total: questions.count)
    }

    /// Shown on the results card — matches server formula when on the universal daily challenge.
    private var displayedXPEarned: Int {
        if dailyChallenge.shouldUseServerDailyCompletion(for: drug) {
            return dailyChallenge.estimatedServerXP(correct: correctCount, total: questions.count)
        }
        return xpEarned
    }

    private var orderedDrugs: [Drug] {
        DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
    }

    private var isTodaysDrugQuiz: Bool {
        progress.isEffectiveTodaysDrug(drug, allDrugs: orderedDrugs)
    }

    private var xpAlreadyAwardedToday: Bool {
        progress.hasAwardedDailyQuizXPToday()
    }

    /// Eligible for daily XP on `Done` — mirrors when we previously showed the +XP celebration (server or legacy).
    private var isFirstAttemptToday: Bool {
        if dailyChallenge.shouldUseServerDailyCompletion(for: drug) {
            return !dailyChallenge.hasServerLoggedCompletionForCurrentAssignment()
        }
        return isTodaysDrugQuiz && !xpAlreadyAwardedToday
    }

    private var scoreFraction: CGFloat {
        let total = max(questions.count, 1)
        return CGFloat(correctCount) / CGFloat(total)
    }

    private var accuracyPercent: Int {
        let total = max(questions.count, 1)
        return Int((Double(correctCount) / Double(total) * 100).rounded())
    }

    /// Past finalized percents for this drug plus the in-progress session (not persisted until Done).
    private var attemptPercentsIncludingCurrent: [Int] {
        let past = progress.drugScores[drug.id] ?? []
        return past + [accuracyPercent]
    }

    /// Up to three rows: last 1–3 attempts with labels `1st att`, `2nd att`, … (ordinals match global attempt index).
    private var quizAttemptHistoryRows: [(label: String, percent: Int)] {
        let full = attemptPercentsIncludingCurrent
        let count = full.count
        guard count > 0 else { return [] }
        let shown = min(3, count)
        let start = count - shown
        return (0..<shown).map { offset in
            let index = start + offset
            let attemptNumber = index + 1
            return (ordinalAttemptLabel(attemptNumber) + " att", full[index])
        }
    }

    private func ordinalAttemptLabel(_ n: Int) -> String {
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

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            if showResults {
                resultsView
                    .transition(.opacity)
            } else if !questions.isEmpty {
                questionView
            } else {
                SwiftUI.ProgressView()
            }
        }
        .onAppear {
            guard questions.isEmpty else { return }
            Task { await loadQuestions() }
        }
        .onChange(of: showResults) { _, isShowing in
            if isShowing {
                scheduleQuizCompleteAnimations()
            } else {
                resetQuizCompleteAnimations()
            }
        }
    }

    private var questionView: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                questionCard
                    .id(currentQuestion.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if hasSubmitted {
                Button(isLastQuestion ? "See Results" : "Next Question →") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isLastQuestion {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showResults = true
                        }
                    } else {
                        withAnimation(.spring(response: 0.62, dampingFraction: 0.72)) {
                            currentIndex += 1
                            selectedAnswers.removeAll()
                            hasSubmitted = false
                        }
                    }
                }
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(.label))
                .foregroundStyle(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
                Button("Submit Answer") {
                    guard canSubmitCurrentQuestion else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        hasSubmitted = true
                        if selectedIsCorrect {
                            correctCount += 1
                        }
                    }
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = selectedIsCorrect ? .heavy : .rigid
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                }
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canSubmitCurrentQuestion ? Color(.label) : Color(.tertiarySystemFill))
                .foregroundStyle(canSubmitCurrentQuestion ? Color(.systemBackground) : Color(.secondaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(!canSubmitCurrentQuestion)
            }
        }
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            questionTypeBadge
            Spacer()
                .frame(height: 16)

            Text(currentQuestion.question)
                .font(theme.appFont(20, weight: .semibold))
                .foregroundStyle(Color(.label))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
                .frame(height: 24)

            VStack(spacing: 10) {
                ForEach(currentQuestion.options, id: \.self) { option in
                    optionButton(option)
                }
            }

            if hasSubmitted {
                Spacer()
                    .frame(height: 14)

                explanationBox
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(24)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(width: 36, height: 36)
                    .background(Color.appInputBackground)
                    .clipShape(Circle())
            }
            .minimumHitTarget()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.black)
                        .frame(width: proxy.size.width * progressValue)
                }
            }
            .frame(height: 6)
        }
    }

    private var progressValue: CGFloat {
        guard !questions.isEmpty else { return 0 }
        return CGFloat(currentIndex) / CGFloat(questions.count)
    }

    private var questionTypeBadge: some View {
        Text(questionTypeLabel)
            .textCase(.uppercase)
            .font(theme.appFont(11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var questionTypeLabel: String {
        if isBonusQuestion {
            return "BONUS:"
        }
        return currentQuestion.isMultiSelect ? "MULTI SELECT" : "MULTIPLE CHOICE"
    }

    private var isBonusQuestion: Bool {
        currentQuestion.drugId.hasPrefix("class-")
    }

    private func optionButton(_ option: String) -> some View {
        let isSelected = selectedAnswers.contains(option)
        let isCorrectOption = containsNormalized(currentQuestion.correctAnswers, value: option)
        let showCorrectReveal = hasSubmitted && isCorrectOption && !isSelected
        let isWrongReveal = hasSubmitted && isSelected && !isCorrectOption
        let isCorrectSelected = hasSubmitted && isSelected && isCorrectOption

        let backgroundColor: Color = {
            if isCorrectSelected || showCorrectReveal { return Color.green.opacity(0.15) }
            if isWrongReveal { return Color.red.opacity(0.12) }
            return Color.appCardBackground
        }()

        let borderColor: Color = {
            if isCorrectSelected || showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return Color(.tertiarySystemFill)
        }()

        let textColor: Color = {
            if isCorrectSelected || showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return .primary
        }()

        let iconName: String = {
            if isCorrectSelected || showCorrectReveal { return "checkmark.circle.fill" }
            if isWrongReveal { return "xmark.circle.fill" }
            return isSelected ? "largecircle.fill.circle" : "circle"
        }()

        let iconColor: Color = {
            if isCorrectSelected || showCorrectReveal { return .green }
            if isWrongReveal { return .red }
            return isSelected ? .black : .gray
        }()

        return Button {
            guard !hasSubmitted else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                toggleSelection(for: option)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)

                Text(option)
                    .font(theme.appFont(16, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(nil)
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
    }

    private func toggleSelection(for option: String) {
        if currentQuestion.isMultiSelect {
            if selectedAnswers.contains(option) {
                selectedAnswers.remove(option)
                return
            }
            guard selectedAnswers.count < 2 else { return }
            selectedAnswers.insert(option)
        } else {
            if selectedAnswers.contains(option) {
                selectedAnswers.removeAll()
            } else {
                selectedAnswers = [option]
            }
        }
    }

    private var explanationBox: some View {
        let isCorrect = selectedIsCorrect
        return Text(currentQuestion.explanation)
            .font(theme.appFont(14))
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCorrect ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    resultsHeroHeader
                    resultsScoreRingBlock
                    resultsSummaryCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 16)
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            resultsActionButtons
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                progress.toggleDrugFlag(drug.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: progress.isDrugFlagged(drug.id) ? "flag.fill" : "flag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(progress.isDrugFlagged(drug.id) ? QuizCompleteTheme.warmGold : Color.appSecondaryText)
                    .frame(width: 40, height: 40)
                    .background(Color.appCardBackground)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(QuizCompleteTheme.cardStroke, lineWidth: 1)
                    }
            }
            .minimumHitTarget()
            .accessibilityLabel(progress.isDrugFlagged(drug.id) ? "Unflag drug" : "Flag drug")
            .padding(.trailing, 24)
            .padding(.top, 12)
        }
    }

    private var resultsHeroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(drug.genericName.capitalized)
                .font(.system(size: 40, weight: .semibold, design: .serif).italic())
                .foregroundStyle(QuizCompleteTheme.warmGold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(drug.drugClass)
                .font(.system(size: 14))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(resultsHeaderVisible ? 1 : 0)
        .offset(y: resultsHeaderVisible ? 0 : 10)
    }

    private var resultsScoreRingBlock: some View {
        let total = max(questions.count, 1)

        return VStack(spacing: 18) {
            ZStack {
                QuizCompleteScoreRing(progress: resultsRingProgress, lineWidth: 10, size: 156)

                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(correctCount)")
                            .font(.system(size: 38, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.appPrimaryText)
                        Text("/\(total)")
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.appTertiaryText)
                    }
                    Text("correct")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .frame(height: 196)

            if isFirstAttemptToday {
                VStack(spacing: 8) {
                    Text("+\(displayedXPEarned) XP")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(QuizCompleteTheme.warmGold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(QuizCompleteTheme.warmGold.opacity(0.12))
                        .overlay {
                            Capsule()
                                .strokeBorder(QuizCompleteTheme.warmGold.opacity(0.45), lineWidth: 1)
                        }
                        .clipShape(Capsule())
                        .scaleEffect(resultsXPBadgeVisible ? resultsXPBadgeScale : 0.6)
                        .opacity(resultsXPBadgeVisible ? 1 : 0)

                    if milestoneBadgeVisible, milestoneBonusXp > 0, let day = milestoneDayLabel {
                        Text("🔥 \(day)-day streak · +\(milestoneBonusXp) XP")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(QuizCompleteTheme.warmGold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(QuizCompleteTheme.warmGold.opacity(0.18))
                            .overlay {
                                Capsule()
                                    .strokeBorder(QuizCompleteTheme.warmGold.opacity(0.55), lineWidth: 1)
                            }
                            .clipShape(Capsule())
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
            } else if !isTodaysDrugQuiz {
                Text("Practice mode — XP awarded only on today’s drug")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.appCardBackground)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.appSecondaryText.opacity(0.18), lineWidth: 1)
                    }
                    .clipShape(Capsule())
                    .opacity(resultsXPBadgeVisible ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(accuracyPercent)%")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.appPrimaryText)
                    Text("Accuracy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appTertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(progress.totalXP) XP")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.appPrimaryText)
                    Text("Total XP")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appTertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if !quizAttemptHistoryRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(quizAttemptHistoryRows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.appTertiaryText)
                            Spacer(minLength: 12)
                            Text("\(row.percent)%")
                                .font(.system(size: 17, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.appPrimaryText)
                        }
                    }
                }
                .padding(.top, 20)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: QuizCompleteTheme.summaryCardMinHeight, alignment: .top)
        .padding(16)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: QuizCompleteTheme.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: QuizCompleteTheme.cardCorner, style: .continuous)
                .stroke(QuizCompleteTheme.goldBorder, lineWidth: 1)
        }
        .opacity(resultsCardVisible ? 1 : 0)
        .offset(y: resultsCardVisible ? 0 : 14)
    }

    private var resultsActionButtons: some View {
        VStack(spacing: 12) {
            if let finalizeErrorMessage {
                Text(finalizeErrorMessage)
                    .font(theme.appFont(14, weight: .semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                guard !isFinalizing else { return }
                isFinalizing = true
                Task {
                    let result = await progress.finalizeQuizSession(
                        drug: drug,
                        correctCount: correctCount,
                        totalCount: questions.count,
                        allDrugs: orderedDrugs,
                        source: source
                    )
                    if let err = result.userVisibleError {
                        finalizeErrorMessage = err
                        isFinalizing = false
                        return
                    }
                    if result.milestoneBonus > 0, let day = result.milestoneDay {
                        // Celebrate the streak milestone inline before dismissing — the
                        // user just saw their +daily XP and now sees the bonus stack on top.
                        milestoneBonusXp = result.milestoneBonus
                        milestoneDayLabel = day
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            milestoneBadgeVisible = true
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                    }
                    dismiss()
                }
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.13))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(QuizCompleteTheme.warmGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(isFinalizing ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isFinalizing)

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await restartQuizSession() }
                } label: {
                    Text("Play Again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.appSecondaryText.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Review Card")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.appSecondaryText.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(resultsButtonsVisible ? 1 : 0)
        .offset(y: resultsButtonsVisible ? 0 : 12)
    }

    private func scheduleQuizCompleteAnimations() {
        let token = UUID()
        resultsAnimToken = token
        let fraction = scoreFraction
        let firstXP = isFirstAttemptToday

        withAnimation(.easeOut(duration: 0.42)) {
            resultsHeaderVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard resultsAnimToken == token, showResults else { return }
            withAnimation(QuizCompleteTheme.ringEase) {
                resultsRingProgress = fraction
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard resultsAnimToken == token, showResults else { return }
            withAnimation(.easeOut(duration: 0.48)) {
                resultsCardVisible = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard resultsAnimToken == token, showResults else { return }
            withAnimation(.easeOut(duration: 0.42)) {
                resultsButtonsVisible = true
            }
        }

        if firstXP {
            // Ring runs 0.3s … 1.4s; badge bounces in shortly after it completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.42) {
                guard resultsAnimToken == token, showResults else { return }
                resultsXPBadgeVisible = true
                resultsXPBadgeScale = 0.6
                DispatchQueue.main.async {
                    guard resultsAnimToken == token, showResults else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                        resultsXPBadgeScale = 1.1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        guard resultsAnimToken == token, showResults else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            resultsXPBadgeScale = 1.0
                        }
                    }
                }
            }
        }
    }

    private func resetQuizCompleteAnimations() {
        resultsAnimToken = UUID()
        resultsHeaderVisible = false
        resultsRingProgress = 0
        resultsXPBadgeVisible = false
        resultsXPBadgeScale = 0.6
        resultsCardVisible = false
        resultsButtonsVisible = false
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSet(_ values: Set<String>) -> Set<String> {
        Set(values.map(normalized))
    }

    private func containsNormalized(_ values: [String], value: String) -> Bool {
        let key = normalized(value)
        return values.contains { normalized($0) == key }
    }

    @MainActor
    private func restartQuizSession() async {
        questions = []
        currentIndex = 0
        selectedAnswers = []
        hasSubmitted = false
        correctCount = 0
        showResults = false
        finalizeErrorMessage = nil
        await loadQuestions()
    }

    @MainActor
    private func loadQuestions() async {
        var generated = QuizEngine.generateQuestions(for: drug, allDrugs: orderedDrugs)
        let targetDailyCount = generated.count + 1

        if source == .daily {
            if ClassQuizGuideService.shared.guides.isEmpty {
                await ClassQuizGuideService.shared.loadFromSupabaseOnLaunch()
            }

            var appendedClassBonus = false
            if let bonusQuestion = ClassQuizEngine.generateBonusQuestion(
                for: drug,
                guides: ClassQuizGuideService.shared.guides
            ) {
                generated.append(bonusQuestion)
                appendedClassBonus = true
            }

            if !appendedClassBonus && generated.count < targetDailyCount {
                var signatures = Set(generated.map(questionSignature))
                let engine = QuizEngine(drugs: orderedDrugs)
                var attempts = 0
                while generated.count < targetDailyCount, attempts < 12 {
                    attempts += 1
                    let candidate = engine.generateQuestion(for: drug)
                    let signature = questionSignature(candidate)
                    if signatures.insert(signature).inserted {
                        generated.append(candidate)
                    }
                }
            }
        }

        questions = generated
    }

    private func questionSignature(_ question: QuizQuestion) -> String {
        let answers = question.correctAnswers.map(normalized).sorted().joined(separator: "|")
        return "\(normalized(question.question))::\(answers)"
    }
}

// MARK: - Score ring (vector-style arc, round caps)

private struct QuizCompleteScoreRing: View {
    var progress: CGFloat
    var lineWidth: CGFloat
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: lineWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    QuizCompleteTheme.warmGold,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: QuizCompleteTheme.warmGold.opacity(0.42), radius: 12, y: 3)
        }
    }
}

#Preview {
    QuizView(
        drug: Drug(
            id: "preview",
            genericName: "lisinopril",
            brandNames: ["Zestril"],
            collection: .cardiology,
            subCollection: .aceInhibitors,
            drugClass: "ACE inhibitor",
            mechanismOfAction: "Inhibits ACE enzyme and reduces angiotensin II.",
            indications: ["Hypertension"],
            dosage: Dosage(adult: "10 mg daily", renalAdjustment: "Adjust in CKD", maxDose: "40 mg/day"),
            sideEffects: ["Dry cough"],
            warnings: ["Angioedema"],
            contraindications: ["Pregnancy"],
            interactions: ["NSAIDs"],
            monitoring: ["Blood pressure"],
            counselingPoints: ["Take at the same time each day"],
            pearls: ["Improves outcomes in CKD with proteinuria."]
        )
    )
}
