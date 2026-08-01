import Foundation

enum ClassQuizEngine {
    static func generateBonusQuestion(for drug: Drug, guides: [ClassQuizGuide]) -> QuizQuestion? {
        guard !guides.isEmpty else { return nil }
        let guideBySubCollection = Dictionary(uniqueKeysWithValues: guides.map { ($0.subCollection, $0) })
        guard let guide = guideBySubCollection[drug.subCollection] else { return nil }

        var usedSignatures = Set<String>()
        return buildSingleClassInfoQuestion(for: guide, allGuides: guides, usedSignatures: &usedSignatures)
    }

    static func generateQuestions(
        selectedSubCollections: [SubCollection],
        questionCount: Int,
        allDrugs: [Drug],
        guides: [ClassQuizGuide]
    ) -> [QuizQuestion] {
        let requestedCount = min(max(questionCount, 1), 30)
        let selectedSet = Set(selectedSubCollections)
        let selectedDrugs = allDrugs.filter { selectedSet.contains($0.subCollection) }
        let guideBySubCollection = Dictionary(uniqueKeysWithValues: guides.map { ($0.subCollection, $0) })
        let selectedGuides = selectedSubCollections.compactMap { guideBySubCollection[$0] }

        if selectedDrugs.isEmpty && selectedGuides.isEmpty {
            return []
        }

        var desiredDrugCount = Int((Double(requestedCount) * 0.7).rounded())
        var desiredClassInfoCount = requestedCount - desiredDrugCount

        if selectedDrugs.isEmpty {
            desiredDrugCount = 0
            desiredClassInfoCount = requestedCount
        } else if selectedGuides.isEmpty {
            desiredDrugCount = requestedCount
            desiredClassInfoCount = 0
        }

        var usedSignatures = Set<String>()
        var builtDrugQuestions = buildDrugQuestions(
            selectedDrugs: selectedDrugs,
            desiredCount: desiredDrugCount,
            allDrugs: allDrugs,
            usedSignatures: &usedSignatures
        )
        var builtClassInfoQuestions = buildClassInfoQuestions(
            selectedGuides: selectedGuides,
            desiredCount: desiredClassInfoCount,
            allGuides: guides,
            usedSignatures: &usedSignatures
        )

        var combined = (builtDrugQuestions + builtClassInfoQuestions).shuffled()
        if combined.count >= requestedCount {
            return Array(combined.prefix(requestedCount))
        }

        // Fill any gap while preserving randomness and avoiding exact duplicate prompts.
        let remaining = requestedCount - combined.count
        if !selectedDrugs.isEmpty {
            let extraDrugQuestions = buildDrugQuestions(
                selectedDrugs: selectedDrugs,
                desiredCount: remaining,
                allDrugs: allDrugs,
                usedSignatures: &usedSignatures
            )
            builtDrugQuestions.append(contentsOf: extraDrugQuestions)
        }
        if combined.count + builtDrugQuestions.count < requestedCount, !selectedGuides.isEmpty {
            let needed = requestedCount - (combined.count + builtDrugQuestions.count)
            let extraClassInfoQuestions = buildClassInfoQuestions(
                selectedGuides: selectedGuides,
                desiredCount: needed,
                allGuides: guides,
                usedSignatures: &usedSignatures
            )
            builtClassInfoQuestions.append(contentsOf: extraClassInfoQuestions)
        }

        combined = (combined + builtDrugQuestions + builtClassInfoQuestions).shuffled()
        return Array(combined.prefix(requestedCount))
    }

    private static func buildDrugQuestions(
        selectedDrugs: [Drug],
        desiredCount: Int,
        allDrugs: [Drug],
        usedSignatures: inout Set<String>
    ) -> [QuizQuestion] {
        guard desiredCount > 0, !selectedDrugs.isEmpty else { return [] }

        // Use the full library as distractor source so small class selections
        // still have enough option diversity to produce valid questions.
        let engine = QuizEngine(drugs: allDrugs)
        var results: [QuizQuestion] = []

        // Coverage pass: one per drug first when slots allow.
        for drug in selectedDrugs.shuffled() {
            guard results.count < desiredCount else { break }
            let question = engine.generateQuestion(for: drug)
            let signature = signature(for: question)
            if usedSignatures.insert(signature).inserted {
                results.append(question)
            }
        }

        // Fill remaining slots by rotating random drugs.
        var attempts = 0
        let maxAttempts = max(20, desiredCount * 10)
        while results.count < desiredCount, attempts < maxAttempts {
            attempts += 1
            guard let drug = selectedDrugs.randomElement() else { break }
            let question = engine.generateQuestion(for: drug)
            let signature = signature(for: question)
            if usedSignatures.insert(signature).inserted {
                results.append(question)
            }
        }

        return Array(results.prefix(desiredCount))
    }

    private static func buildClassInfoQuestions(
        selectedGuides: [ClassQuizGuide],
        desiredCount: Int,
        allGuides: [ClassQuizGuide],
        usedSignatures: inout Set<String>
    ) -> [QuizQuestion] {
        guard desiredCount > 0, !selectedGuides.isEmpty else { return [] }

        var results: [QuizQuestion] = []

        // Coverage pass: try one per selected class first.
        for guide in selectedGuides.shuffled() {
            guard results.count < desiredCount else { break }
            if let question = buildSingleClassInfoQuestion(for: guide, allGuides: allGuides, usedSignatures: &usedSignatures) {
                results.append(question)
            }
        }

        // Fill pass with random selected classes.
        var attempts = 0
        let maxAttempts = max(20, desiredCount * 12)
        while results.count < desiredCount, attempts < maxAttempts {
            attempts += 1
            guard let guide = selectedGuides.randomElement() else { break }
            if let question = buildSingleClassInfoQuestion(for: guide, allGuides: allGuides, usedSignatures: &usedSignatures) {
                results.append(question)
            }
        }

        return Array(results.prefix(desiredCount))
    }

    private static func buildSingleClassInfoQuestion(
        for guide: ClassQuizGuide,
        allGuides: [ClassQuizGuide],
        usedSignatures: inout Set<String>
    ) -> QuizQuestion? {
        let questionBuilders: [() -> QuizQuestion?] = [
            { buildSuffixQuestion(for: guide, allGuides: allGuides) },
            { buildClassUseQuestion(for: guide, allGuides: allGuides) },
            { buildSideEffectQuestion(for: guide, allGuides: allGuides) },
            { buildHighRiskQuestion(for: guide, allGuides: allGuides) },
            { buildPearlQuestion(for: guide, allGuides: allGuides) }
        ]

        for builder in questionBuilders.shuffled() {
            guard let question = builder() else { continue }
            let key = signature(for: question)
            if usedSignatures.insert(key).inserted {
                return question
            }
        }
        return nil
    }

    private static func buildSuffixQuestion(for guide: ClassQuizGuide, allGuides: [ClassQuizGuide]) -> QuizQuestion? {
        guard let correct = guide.suffixes.randomElement() else { return nil }
        let distractorPool = allGuides
            .filter { $0.subCollection != guide.subCollection }
            .flatMap(\.suffixes)
        guard let options = buildOptions(correct: correct, distractorPool: distractorPool, fallbackPool: allSuffixes(from: allGuides)) else {
            return nil
        }

        return QuizQuestion(
            id: UUID(),
            drugId: "class-\(guide.subCollection)",
            question: "Which suffix is most associated with \(guide.displayName)?",
            options: options,
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: "\(correct) is a key suffix pattern for \(guide.displayName)."
        )
    }

    private static func buildClassUseQuestion(for guide: ClassQuizGuide, allGuides: [ClassQuizGuide]) -> QuizQuestion? {
        guard let correct = guide.classUses.randomElement() else { return nil }
        let distractorPool = allGuides
            .filter { $0.subCollection != guide.subCollection }
            .flatMap(\.classUses)
        let fallback = allGuides.flatMap(\.classUses)
        guard let options = buildOptions(correct: correct, distractorPool: distractorPool, fallbackPool: fallback) else {
            return nil
        }

        return QuizQuestion(
            id: UUID(),
            drugId: "class-\(guide.subCollection)",
            question: "Which condition is a common use for \(guide.displayName)?",
            options: options,
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: "\(correct) is one of the core uses associated with \(guide.displayName)."
        )
    }

    private static func buildSideEffectQuestion(for guide: ClassQuizGuide, allGuides: [ClassQuizGuide]) -> QuizQuestion? {
        guard let correct = guide.hallmarkSideEffects.randomElement() else { return nil }
        let distractorPool = allGuides
            .filter { $0.subCollection != guide.subCollection }
            .flatMap(\.hallmarkSideEffects)
        let fallback = allGuides.flatMap(\.hallmarkSideEffects)
        guard let options = buildOptions(correct: correct, distractorPool: distractorPool, fallbackPool: fallback) else {
            return nil
        }

        return QuizQuestion(
            id: UUID(),
            drugId: "class-\(guide.subCollection)",
            question: "Which adverse effect is high-yield for \(guide.displayName)?",
            options: options,
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: "\(correct) is a hallmark side effect for \(guide.displayName)."
        )
    }

    private static func buildHighRiskQuestion(for guide: ClassQuizGuide, allGuides: [ClassQuizGuide]) -> QuizQuestion? {
        guard let correct = guide.highRiskMeds.randomElement() else { return nil }
        let distractorPool = allGuides
            .filter { $0.subCollection != guide.subCollection }
            .flatMap(\.highRiskMeds)
        let fallback = allGuides.flatMap(\.highRiskMeds)
        guard let options = buildOptions(correct: correct, distractorPool: distractorPool, fallbackPool: fallback) else {
            return nil
        }

        return QuizQuestion(
            id: UUID(),
            drugId: "class-\(guide.subCollection)",
            question: "Which medication is listed as high-risk in \(guide.displayName)?",
            options: options,
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: "\(correct) is tagged as high-risk in your class guide for \(guide.displayName)."
        )
    }

    private static func buildPearlQuestion(for guide: ClassQuizGuide, allGuides: [ClassQuizGuide]) -> QuizQuestion? {
        guard let correct = guide.highYieldPearls.randomElement() else { return nil }
        let distractorPool = allGuides
            .filter { $0.subCollection != guide.subCollection }
            .flatMap(\.highYieldPearls)
        let fallback = allGuides.flatMap(\.highYieldPearls)
        guard let options = buildOptions(correct: correct, distractorPool: distractorPool, fallbackPool: fallback) else {
            return nil
        }

        return QuizQuestion(
            id: UUID(),
            drugId: "class-\(guide.subCollection)",
            question: "Which statement is true about \(guide.displayName)?",
            options: options,
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: "This is a high-yield pearl for \(guide.displayName)."
        )
    }

    private static func allSuffixes(from guides: [ClassQuizGuide]) -> [String] {
        guides.flatMap(\.suffixes)
    }

    private static func buildOptions(correct: String, distractorPool: [String], fallbackPool: [String]) -> [String]? {
        let normalizedCorrect = normalize(correct)
        guard !normalizedCorrect.isEmpty else { return nil }

        var dedupedDistractors = orderedUnique(distractorPool)
            .filter { normalize($0) != normalizedCorrect }
            .shuffled()
        if dedupedDistractors.count < 4 {
            let fallback = orderedUnique(fallbackPool).filter {
                let key = normalize($0)
                return key != normalizedCorrect && !dedupedDistractors.contains(where: { normalize($0) == key })
            }
            dedupedDistractors.append(contentsOf: fallback.shuffled())
        }

        let selected = Array(dedupedDistractors.prefix(4))
        guard selected.count == 4 else { return nil }
        return ([correct] + selected).shuffled()
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                output.append(trimmed)
            }
        }
        return output
    }

    private static func signature(for question: QuizQuestion) -> String {
        let optionsSignature = question.options.sorted().joined(separator: "|")
        return "\(question.question.lowercased())::\(optionsSignature.lowercased())"
    }

    /// Delegate to `QuizEngine.normalizedKey` so bonus questions dedupe and answer-match
    /// the same way the rest of the quiz pipeline does (audit P1 #12). The previous looser
    /// scheme (no punctuation strip) meant `QuizView`'s matcher (now strict) could mark a
    /// punctuation-only-different distractor as correct.
    private static func normalize(_ value: String) -> String {
        QuizEngine.normalizedKey(value)
    }
}
