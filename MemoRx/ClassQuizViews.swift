import SwiftUI
import UIKit

private struct ClassQuizSession: Identifiable {
    let id = UUID()
    let title: String
    let selectedSubCollections: [SubCollection]
    let selectedClassNames: [String]
    let questions: [QuizQuestion]
    let requestedQuestionCount: Int
}

struct QuizCuratorView: View {
    @Environment(\.appTheme) private var theme
    let allDrugs: [Drug]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubCollections: Set<SubCollection> = []
    @State private var questionCount: Double = 10
    @State private var activeQuiz: ClassQuizSession?

    private var guides: [ClassQuizGuide] {
        ClassQuizGuideService.shared.guides
    }

    private var guideBySubCollection: [SubCollection: ClassQuizGuide] {
        Dictionary(uniqueKeysWithValues: guides.map { ($0.subCollection, $0) })
    }

    private var availableSubCollections: [SubCollection] {
        let fromGuides = Set(guides.map(\.subCollection))
        let fromDrugs = Set(allDrugs.map(\.subCollection))
        return Array(fromGuides.union(fromDrugs)).sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    private var hasClassContent: Bool {
        !guides.isEmpty
    }

    private var hasSelection: Bool {
        !selectedSubCollections.isEmpty
    }

    private var allSelected: Bool {
        !availableSubCollections.isEmpty && selectedSubCollections.count == availableSubCollections.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        introCard
                        questionCountCard
                        classSelectionCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Quiz Curator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, MemoToolbarPillMetrics.horizontalPadding)
                            .padding(.vertical, MemoToolbarPillMetrics.verticalPadding)
                            .topBarPillChrome()
                    }
                    .minimumHitTarget()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start Quiz") {
                        startQuiz()
                    }
                    .font(theme.appFont(14, weight: .semibold))
                    .disabled(!hasSelection || !hasClassContent)
                }
            }
            .fullScreenCover(item: $activeQuiz) { session in
                ClassQuizView(
                    title: session.title,
                    selectedSubCollections: session.selectedSubCollections,
                    selectedClassNames: session.selectedClassNames,
                    questions: session.questions,
                    requestedQuestionCount: session.requestedQuestionCount,
                    onDone: { dismiss() }
                )
            }
            .onAppear {
                if ClassQuizGuideService.shared.guides.isEmpty {
                    Task {
                        await ClassQuizGuideService.shared.loadFromSupabaseOnLaunch()
                    }
                }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Build a custom quiz from one class, many classes, or all classes.")
                .font(theme.appFont(14))
                .foregroundStyle(.secondary)

            if !hasClassContent {
                Text(ClassQuizGuideService.shared.loadErrorMessage ?? "Class quiz content couldn't be loaded.")
                    .font(theme.appFont(13, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var questionCountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Question Count")
                    .font(theme.appFont(16, weight: .semibold))
                Spacer()
                Text("\(Int(questionCount))")
                    .font(theme.appFont(16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $questionCount, in: 10...30, step: 1)
                .tint(.black)

            Text("70% questions from selected drugs, 30% from class guide points.")
                .font(theme.appFont(12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var classSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Classes")
                    .font(theme.appFont(16, weight: .semibold))

                Spacer()

                Button(allSelected ? "Clear All" : "Select All") {
                    toggleSelectAll()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .font(theme.appFont(13, weight: .semibold))
            }

            ForEach(availableSubCollections, id: \.self) { subCollection in
                classRow(subCollection)
            }
        }
        .padding(16)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func classRow(_ subCollection: SubCollection) -> some View {
        let selected = selectedSubCollections.contains(subCollection)
        let drugCount = allDrugs.filter { $0.subCollection == subCollection }.count

        return Button {
            toggleSelection(for: subCollection)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? .black : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(for: subCollection))
                        .font(theme.appFont(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(drugCount) drugs")
                        .font(theme.appFont(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
    }

    private func displayName(for subCollection: SubCollection) -> String {
        guideBySubCollection[subCollection]?.displayName ?? subCollection.displayName
    }

    private func toggleSelection(for subCollection: SubCollection) {
        if selectedSubCollections.contains(subCollection) {
            selectedSubCollections.remove(subCollection)
        } else {
            selectedSubCollections.insert(subCollection)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedSubCollections.removeAll()
        } else {
            selectedSubCollections = Set(availableSubCollections)
        }
    }

    private func startQuiz() {
        guard hasSelection else { return }

        let orderedSelection = selectedSubCollections.sorted { displayName(for: $0) < displayName(for: $1) }
        let generated = ClassQuizEngine.generateQuestions(
            selectedSubCollections: orderedSelection,
            questionCount: Int(questionCount),
            allDrugs: allDrugs,
            guides: guides
        )
        guard !generated.isEmpty else { return }

        let classNames = orderedSelection.map(displayName(for:))
        let title = classNames.count == 1 ? "\(classNames[0]) Class Quiz" : "Custom Class Quiz"
        activeQuiz = ClassQuizSession(
            title: title,
            selectedSubCollections: orderedSelection,
            selectedClassNames: classNames,
            questions: generated,
            requestedQuestionCount: Int(questionCount)
        )
    }
}

struct ClassQuizView: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let selectedSubCollections: [SubCollection]
    let selectedClassNames: [String]
    let questions: [QuizQuestion]
    let requestedQuestionCount: Int
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progress = UserProgressService.shared

    @State private var currentIndex = 0
    @State private var selectedAnswers: Set<String> = []
    @State private var hasSubmitted = false
    @State private var correctCount = 0
    @State private var showResults = false

    private var currentQuestion: QuizQuestion {
        questions[currentIndex]
    }

    private var hasValidCurrentQuestion: Bool {
        questions.indices.contains(currentIndex)
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

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            if showResults {
                resultsView
                    .transition(.opacity)
            } else if hasValidCurrentQuestion {
                questionView
            } else {
                invalidStateView
            }
        }
        .onAppear {
            clampCurrentIndexIfNeeded()
        }
        .onChange(of: questions.count) { _, _ in
            clampCurrentIndexIfNeeded()
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

    private var invalidStateView: some View {
        VStack(spacing: 18) {
            Text("Unable to Load Quiz")
                .font(theme.appFont(24, weight: .bold))
            Text("Please close and start the class quiz again.")
                .font(theme.appFont(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(.label))
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
        }
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
        Text(currentQuestion.isMultiSelect ? "MULTI SELECT" : "MULTIPLE CHOICE")
            .textCase(.uppercase)
            .font(theme.appFont(11, weight: .semibold))
            .foregroundStyle(.secondary)
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
        VStack(spacing: 0) {
            Spacer()

            Text("Quiz Complete")
                .font(theme.appFont(28, weight: .bold))

            Text(title)
                .font(theme.appFont(18, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if selectedClassNames.count > 1 {
                Text(selectedClassNames.joined(separator: " • "))
                    .font(theme.appFont(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }

            Spacer()
                .frame(height: 24)

            Circle()
                .strokeBorder(Color(.label), lineWidth: 6)
                .frame(width: 140, height: 140)
                .overlay {
                    VStack(spacing: 4) {
                        Text("\(correctCount)/\(questions.count)")
                            .font(theme.appFont(36, weight: .bold))
                        Text("correct")
                            .font(theme.appFont(14))
                            .foregroundStyle(.secondary)
                    }
                }

            Spacer()
                .frame(height: 18)

            Text("Class quizzes are study-only and do not award XP.")
                .font(theme.appFont(16, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
                .frame(height: 40)

            VStack(spacing: 12) {
                Button("Done") {
                    progress.recordClassQuizAttempt(
                        selectedSubCollections: selectedSubCollections,
                        selectedClassNames: selectedClassNames,
                        questionCount: requestedQuestionCount,
                        correctCount: correctCount,
                        totalCount: questions.count
                    )
                    onDone?()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(.label))
                .foregroundStyle(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("Review Questions") {
                    currentIndex = 0
                    selectedAnswers.removeAll()
                    hasSubmitted = false
                    correctCount = 0
                    showResults = false
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.appCardBackground)
                .foregroundStyle(Color(.label))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.label), lineWidth: 1)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
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

    private func clampCurrentIndexIfNeeded() {
        guard !questions.isEmpty else {
            currentIndex = 0
            return
        }
        if currentIndex < 0 {
            currentIndex = 0
        } else         if currentIndex >= questions.count {
            currentIndex = questions.count - 1
        }
    }
}
