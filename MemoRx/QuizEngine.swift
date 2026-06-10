import Foundation

struct QuizQuestion {
    let id: UUID
    let drugId: String
    let question: String
    let options: [String]
    let correctAnswers: [String]
    let isMultiSelect: Bool
    let explanation: String
}

final class QuizEngine {
    let drugs: [Drug]
    private var lastQuestionSignature: String?
    private var recentQuestionModes: [Bool] = [] // true = multi-select, false = single-answer

    init(drugs: [Drug]) {
        self.drugs = drugs
    }

    func generateQuestion(for drug: Drug) -> QuizQuestion {
        var usedFieldTypes = Set<String>()
        if let question = generateQuestionOrNil(
            for: drug,
            maxFieldRetries: QuestionFieldType.quizCases.count * 3,
            usedFieldTypes: &usedFieldTypes
        ) {
            return question
        }

        // Keep quiz flow resilient even when a specific drug/class subset can't
        // satisfy strict option-generation constraints in debug builds.
        #if DEBUG
        print("QuizEngine fallback: unable to generate strict question for drug \(drug.id)")
        #endif
        return emergencyFallbackQuestion(for: drug)
    }

    static func generateQuestions(for drug: Drug, allDrugs: [Drug], count: Int = 7) -> [QuizQuestion] {
        let engine = QuizEngine(drugs: allDrugs)
        let safeCount = max(1, count)
        var questions: [QuizQuestion] = []
        questions.reserveCapacity(safeCount)
        let maxMultiSelect = safeCount >= 7 ? 3 : max(1, safeCount / 2)
        var multiSelectCount = 0
        var attempts = 0
        let maxAttempts = safeCount * 6
        var usedFieldTypes = Set<String>()

        while questions.count < safeCount, attempts < maxAttempts {
            let forceSingle = multiSelectCount >= maxMultiSelect
            if let question = engine.generateQuestionOrNil(
                for: drug,
                maxFieldRetries: QuestionFieldType.quizCases.count * 3,
                forceSingleAnswer: forceSingle,
                usedFieldTypes: &usedFieldTypes
            ) {
                questions.append(question)
                if question.isMultiSelect {
                    multiSelectCount += 1
                }
            }
            attempts += 1
        }

        return questions
    }

    private func generateQuestionOrNil(
        for drug: Drug,
        maxFieldRetries: Int,
        forceSingleAnswer: Bool = false,
        usedFieldTypes: inout Set<String>
    ) -> QuizQuestion? {
        let fieldTypes = QuestionFieldType.quizCases
        guard !fieldTypes.isEmpty else { return nil }

        let forceByStreak = recentQuestionModes.suffix(2).count == 2 &&
            recentQuestionModes.suffix(2).allSatisfy { $0 }
        let mustUseSingle = forceSingleAnswer || forceByStreak
        let candidateTypes: [QuestionFieldType]
        if mustUseSingle {
            let singles = fieldTypes.filter { !$0.isMultiSelect }
            candidateTypes = singles.isEmpty ? fieldTypes : singles
        } else {
            candidateTypes = fieldTypes
        }

        let retries = max(maxFieldRetries, candidateTypes.count)
        for attempt in 0..<retries {
            let ordered = (attempt % candidateTypes.count == 0) ? candidateTypes.shuffled() : candidateTypes
            let fieldType = ordered[attempt % candidateTypes.count]
            if usedFieldTypes.contains(fieldType.rawValue) {
                continue
            }
            let signature = questionSignature(drugId: drug.id, fieldType: fieldType)
            if signature == lastQuestionSignature {
                continue
            }
            if let question = buildQuestion(for: drug, fieldType: fieldType) {
                usedFieldTypes.insert(fieldType.rawValue)
                lastQuestionSignature = signature
                recordQuestionMode(isMultiSelect: question.isMultiSelect)
                return question
            }
        }

        // If all retries fail, allow same field as last attempt.
        for fieldType in candidateTypes {
            if usedFieldTypes.contains(fieldType.rawValue) {
                continue
            }
            if let question = buildQuestion(for: drug, fieldType: fieldType) {
                usedFieldTypes.insert(fieldType.rawValue)
                lastQuestionSignature = questionSignature(drugId: drug.id, fieldType: fieldType)
                recordQuestionMode(isMultiSelect: question.isMultiSelect)
                return question
            }
        }

        return nil
    }

    private func buildQuestion(for drug: Drug, fieldType: QuestionFieldType) -> QuizQuestion? {
        if fieldType == .nameMapping {
            return buildNameMappingQuestion(for: drug)
        }

        let valuesForDrug = normalizedValues(for: drug, fieldType: fieldType)
        guard !valuesForDrug.isEmpty else { return nil }

        let neededCorrectCount = fieldType.isMultiSelect ? 2 : 1
        let correctAnswers = pickDistinctByConcept(from: valuesForDrug, count: neededCorrectCount)
        guard correctAnswers.count == neededCorrectCount else { return nil }

        let correctPoolNormalized = Set(valuesForDrug.map(normalizedKey))
        let correctPoolConcept = Set(valuesForDrug.map(conceptKey))
        let distractorCount = 5 - correctAnswers.count

        let distractors = generateDistractors(
            for: drug,
            fieldType: fieldType,
            needed: distractorCount,
            blockedNormalized: correctPoolNormalized,
            blockedConcept: correctPoolConcept
        )
        guard distractors.count == distractorCount else { return nil }

        let options = removeConceptDuplicates(correctAnswers + distractors)
        guard options.count == 5 else { return nil }

        return QuizQuestion(
            id: UUID(),
            drugId: drug.id,
            question: fieldType.prompt(for: drug.genericName),
            options: options.shuffled(),
            correctAnswers: correctAnswers,
            isMultiSelect: fieldType.isMultiSelect,
            explanation: fieldType.explanation(for: drug.genericName)
        )
    }

    private func buildNameMappingQuestion(for drug: Drug) -> QuizQuestion? {
        let genericName = drug.genericName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !genericName.isEmpty else { return nil }

        let validBrands = removeConceptDuplicates(
            drug.brandNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        guard !validBrands.isEmpty else { return nil }

        let askForGeneric = Bool.random()
        if askForGeneric {
            guard let referenceBrand = validBrands.randomElement() else { return nil }

            let blockedNormalized = Set([normalizedKey(genericName)])
            let blockedConcept = Set([conceptKey(genericName)])
            let distractors = generateDistractors(
                for: drug,
                fieldType: .genericName,
                needed: 4,
                blockedNormalized: blockedNormalized,
                blockedConcept: blockedConcept
            )
            guard distractors.count == 4 else { return nil }

            let options = removeConceptDuplicates([genericName] + distractors)
            guard options.count == 5 else { return nil }

            return QuizQuestion(
                id: UUID(),
                drugId: drug.id,
                question: "What's the generic name of \(referenceBrand)?",
                options: options.shuffled(),
                correctAnswers: [genericName],
                isMultiSelect: false,
                explanation: "\(referenceBrand) is a brand name for \(genericName)."
            )
        }

        guard let referenceBrand = validBrands.randomElement() else { return nil }
        let blockedNormalized = Set(validBrands.map(normalizedKey))
        let blockedConcept = Set(validBrands.map(conceptKey))
        let distractors = generateDistractors(
            for: drug,
            fieldType: .brandNames,
            needed: 4,
            blockedNormalized: blockedNormalized,
            blockedConcept: blockedConcept
        )
        guard distractors.count == 4 else { return nil }

        let options = removeConceptDuplicates([referenceBrand] + distractors)
        guard options.count == 5 else { return nil }

        let allBrands = validBrands.joined(separator: ", ")
        return QuizQuestion(
            id: UUID(),
            drugId: drug.id,
            question: "What's a brand name of \(genericName)?",
            options: options.shuffled(),
            correctAnswers: [referenceBrand],
            isMultiSelect: false,
            explanation: "\(genericName) is marketed as \(allBrands)."
        )
    }

    private func generateDistractors(
        for drug: Drug,
        fieldType: QuestionFieldType,
        needed: Int,
        blockedNormalized: Set<String>,
        blockedConcept: Set<String>
    ) -> [String] {
        let candidateStages = collectCandidates(for: drug, fieldType: fieldType)
        var selected: [String] = []

        // Strict pass: semantic/concept filtering ON.
        for stage in candidateStages {
            selected = filterCandidates(
                candidates: stage,
                existing: selected,
                blockedNormalized: blockedNormalized,
                blockedConcept: blockedConcept,
                maxCount: needed,
                useConceptFiltering: true
            )
            if selected.count >= needed {
                return Array(selected.prefix(needed))
            }
        }

        // For single-answer questions, immediately widen to all drugs with relaxed concept filtering.
        if !fieldType.isMultiSelect, selected.count < needed {
            let allOtherDrugs = drugs.filter { $0.id != drug.id }
            let globalCandidates = flattenValues(from: allOtherDrugs, fieldType: fieldType)
            selected = filterCandidates(
                candidates: globalCandidates,
                existing: selected,
                blockedNormalized: blockedNormalized,
                blockedConcept: blockedConcept,
                maxCount: needed,
                useConceptFiltering: false
            )
            if selected.count >= needed {
                return Array(selected.prefix(needed))
            }
        }

        // Relaxed pass: semantic/concept filtering OFF, normalized filtering still ON.
        for stage in candidateStages {
            selected = filterCandidates(
                candidates: stage,
                existing: selected,
                blockedNormalized: blockedNormalized,
                blockedConcept: blockedConcept,
                maxCount: needed,
                useConceptFiltering: false
            )
            if selected.count >= needed {
                return Array(selected.prefix(needed))
            }
        }

        return Array(selected.prefix(needed))
    }

    private func collectCandidates(for drug: Drug, fieldType: QuestionFieldType) -> [[String]] {
        let sameClass = drugs.filter { $0.id != drug.id && $0.drugClass == drug.drugClass }
        let sameCollection = drugs.filter {
            $0.id != drug.id &&
            $0.collection == drug.collection &&
            $0.drugClass != drug.drugClass
        }
        let allOthers = drugs.filter { $0.id != drug.id }

        return [
            flattenValues(from: sameClass, fieldType: fieldType),
            flattenValues(from: sameCollection, fieldType: fieldType),
            flattenValues(from: allOthers, fieldType: fieldType)
        ]
    }

    private func filterCandidates(
        candidates: [String],
        existing: [String],
        blockedNormalized: Set<String>,
        blockedConcept: Set<String>,
        maxCount: Int,
        useConceptFiltering: Bool
    ) -> [String] {
        var result = existing
        var usedNormalized = Set(result.map(normalizedKey))
        var usedConcept = Set(result.map(conceptKey))

        for candidate in candidates.shuffled() {
            let normalized = normalizedKey(candidate)
            let concept = conceptKey(candidate)
            guard !normalized.isEmpty else { continue }
            guard !blockedNormalized.contains(normalized) else { continue }
            guard !usedNormalized.contains(normalized) else { continue }

            if useConceptFiltering {
                guard !blockedConcept.contains(concept) else { continue }
                guard !usedConcept.contains(concept) else { continue }
            }

            result.append(candidate)
            usedNormalized.insert(normalized)
            usedConcept.insert(concept)

            if result.count >= maxCount {
                break
            }
        }

        return result
    }

    private func normalizedValues(for drug: Drug, fieldType: QuestionFieldType) -> [String] {
        let rawValues: [String]
        switch fieldType {
        case .mechanismOfAction:
            rawValues = [drug.mechanismOfAction]
        case .nameMapping:
            // Name-mapping questions are built by a dedicated builder.
            // Keep this exhaustive with a safe fallback representation.
            rawValues = [drug.genericName]
        case .genericName:
            rawValues = [drug.genericName]
        case .brandNames:
            rawValues = drug.brandNames
        case .indications:
            rawValues = drug.indications
        case .adultDosage:
            rawValues = [drug.dosage.adult]
        case .sideEffects:
            rawValues = drug.sideEffects
        case .contraindications:
            rawValues = drug.contraindications
        case .interactions:
            rawValues = drug.interactions
        case .pearls:
            rawValues = drug.pearls
        }

        return removeConceptDuplicates(rawValues.map { readableValue($0, fieldType: fieldType) })
    }

    private func flattenValues(from sourceDrugs: [Drug], fieldType: QuestionFieldType) -> [String] {
        let flattened = sourceDrugs.flatMap { normalizedValues(for: $0, fieldType: fieldType) }
        return removeConceptDuplicates(flattened)
    }

    private func removeConceptDuplicates(_ values: [String]) -> [String] {
        var normalizedSeen = Set<String>()
        var conceptSeen = Set<String>()
        var deduped: [String] = []

        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            let normalized = normalizedKey(cleaned)
            // Drop values that normalize to empty (e.g. "—", "•", "?", ".") — these render
            // as a near-blank quiz answer and have no alphanumeric content to grade against.
            // Audit P1 #4 / "blank answers" repro: previously the `pickDistinctByConcept`
            // path could pick a punctuation-only string from a sparse field array.
            guard !normalized.isEmpty else { continue }
            let concept = conceptKey(cleaned)
            guard normalizedSeen.insert(normalized).inserted else { continue }
            guard conceptSeen.insert(concept).inserted else { continue }
            deduped.append(cleaned)
        }

        return deduped
    }

    private func pickDistinctByConcept(from values: [String], count: Int) -> [String] {
        guard count > 0 else { return [] }
        var picked: [String] = []
        var seenConcepts = Set<String>()

        for value in values.shuffled() {
            let concept = conceptKey(value)
            guard seenConcepts.insert(concept).inserted else { continue }
            picked.append(value)
            if picked.count == count {
                break
            }
        }

        return picked
    }

    private func readableValue(_ input: String, fieldType: QuestionFieldType) -> String {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return "" }

        // Catalog bullets should appear in full so options match the card and are not cut mid-phrase.
        // Only cap extremely long single strings so layouts stay usable; prefer word-boundary ellipsis.
        if fieldType == .mechanismOfAction {
            if let periodRange = trimmed.range(of: ". ") {
                let firstSentence = String(trimmed[..<periodRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if firstSentence.count >= 40, firstSentence.count < trimmed.count {
                    return softCap(firstSentence, maxLength: 420, appendEllipsis: true)
                }
            }
            if let periodIndex = trimmed.firstIndex(of: "."), periodIndex < trimmed.index(before: trimmed.endIndex) {
                let firstSentence = String(trimmed[...periodIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if firstSentence.count >= 40 {
                    return softCap(firstSentence, maxLength: 420, appendEllipsis: true)
                }
            }
            return softCap(trimmed, maxLength: 420, appendEllipsis: true)
        }

        return softCap(trimmed, maxLength: 520, appendEllipsis: true)
    }

    /// Truncates only when over `maxLength`, breaking at a word boundary and appending an ellipsis when trimming.
    private func softCap(_ value: String, maxLength: Int, appendEllipsis: Bool) -> String {
        guard value.count > maxLength else { return value }
        return clip(value, maxLength: maxLength, appendEllipsis: appendEllipsis)
    }

    private func clip(_ value: String, maxLength: Int, appendEllipsis: Bool) -> String {
        guard value.count > maxLength else { return value }
        let tentativeEnd = value.index(value.startIndex, offsetBy: maxLength)
        let prefix = String(value[..<tentativeEnd])
        let pieces = prefix.split(separator: " ")
        let clipped = pieces.dropLast().isEmpty ? prefix : pieces.dropLast().joined(separator: " ")
        let clean = clipped.trimmingCharacters(in: .whitespacesAndNewlines)
        if appendEllipsis, clean.count < value.trimmingCharacters(in: .whitespacesAndNewlines).count {
            return clean + "…"
        }
        return clean
    }

    /// Shared canonical normalization for distractor de-duplication AND user-answer
    /// matching in `QuizView`. Audit P1 #12: previously `QuizView` had a looser
    /// scheme (fold + lowercase + trim only) that could miss matches when punctuation
    /// or whitespace differed between the option label and the stored correct value.
    static func normalizedKey(_ value: String) -> String {
        let lower = value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let punctuationRemoved = lower.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )
        let collapsed = punctuationRemoved.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ value: String) -> String {
        Self.normalizedKey(value)
    }

    private func conceptKey(_ value: String) -> String {
        let normalized = normalizedKey(value)
        if normalized.isEmpty { return normalized }

        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "of", "with", "without", "if", "both",
            "risk", "may", "can", "to", "in", "on", "for", "at", "is", "are",
            "first", "second", "third", "degree", "1st", "2nd", "3rd",
            "mild", "severe", "acute", "chronic", "symptom", "symptoms", "oral",
            "masked", "masking", "additive", "potential", "possible", "cause", "causing"
        ]
        let synonymMap: [String: String] = [
            "antidiabetics": "antidiabetic",
            "hypoglycemics": "antidiabetic",
            "hypoglycemic": "antidiabetic",
            "hypoglycemia": "antidiabetic",
            "hypogly": "antidiabetic",
            "insulin": "antidiabetic",
            "blockers": "blocker",
            "calcium": "ccb",
            "channel": "ccb"
        ]

        let tokens = normalized
            .split(separator: " ")
            .map(String.init)
            .map { token -> String in
                if token.hasPrefix("hypoglyc") { return "antidiabetic" }
                if let mapped = synonymMap[token] { return mapped }
                if token.hasSuffix("s"), token.count > 3 {
                    return String(token.dropLast())
                }
                return token
            }
            .filter { !stopwords.contains($0) && !$0.isEmpty }

        let uniqueSorted = Array(Set(tokens)).sorted()
        return uniqueSorted.joined(separator: " ")
    }

    private func questionSignature(drugId: String, fieldType: QuestionFieldType) -> String {
        "\(drugId)::\(fieldType.rawValue)"
    }

    private func recordQuestionMode(isMultiSelect: Bool) {
        recentQuestionModes.append(isMultiSelect)
        if recentQuestionModes.count > 4 {
            recentQuestionModes.removeFirst(recentQuestionModes.count - 4)
        }
    }

    private func emergencyFallbackQuestion(for drug: Drug) -> QuizQuestion {
        let fallbackField: QuestionFieldType = .mechanismOfAction
        let values = normalizedValues(for: drug, fieldType: fallbackField)
        let correct = values.first ?? drug.genericName
        let blocked = Set(values.map(normalizedKey))
        let blockedConcept = Set(values.map(conceptKey))
        let distractors = generateDistractors(
            for: drug,
            fieldType: fallbackField,
            needed: 4,
            blockedNormalized: blocked,
            blockedConcept: blockedConcept
        )
        let options = removeConceptDuplicates([correct] + distractors).shuffled()

        return QuizQuestion(
            id: UUID(),
            drugId: drug.id,
            question: fallbackField.prompt(for: drug.genericName),
            options: Array(options.prefix(5)),
            correctAnswers: [correct],
            isMultiSelect: false,
            explanation: fallbackField.explanation(for: drug.genericName)
        )
    }
}

private enum QuestionFieldType: String, CaseIterable {
    case mechanismOfAction
    case nameMapping
    case genericName
    case brandNames
    case indications
    case adultDosage
    case sideEffects
    case contraindications
    case interactions
    case pearls

    static var quizCases: [QuestionFieldType] {
        allCases.filter { !$0.isHelperValueType }
    }

    private var isHelperValueType: Bool {
        switch self {
        case .genericName, .brandNames:
            return true
        default:
            return false
        }
    }

    var isMultiSelect: Bool {
        switch self {
        case .mechanismOfAction, .nameMapping, .genericName, .brandNames, .adultDosage:
            return false
        case .indications, .sideEffects, .contraindications, .interactions, .pearls:
            return true
        }
    }

    func prompt(for genericName: String) -> String {
        switch self {
        case .mechanismOfAction:
            return "What is the mechanism of action of \(genericName)?"
        case .nameMapping:
            return "Which name correctly matches \(genericName)?"
        case .genericName:
            return "What is the generic name of this drug?"
        case .brandNames:
            return "What is a brand name of \(genericName)?"
        case .indications:
            return "Which of the following are indications for \(genericName)? (Select 2)"
        case .adultDosage:
            return "What is the typical adult dose of \(genericName)?"
        case .sideEffects:
            return "Which of the following are side effects of \(genericName)? (Select 2)"
        case .contraindications:
            return "Which of the following are contraindications for \(genericName)? (Select 2)"
        case .interactions:
            return "Which of the following are drug interactions with \(genericName)? (Select 2)"
        case .pearls:
            return "Which of the following are key clinical pearls for \(genericName)? (Select 2)"
        }
    }

    func explanation(for genericName: String) -> String {
        switch self {
        case .mechanismOfAction:
            return "\(genericName) has this mechanism of action."
        case .nameMapping:
            return "Review this drug's generic and brand name pairing."
        case .genericName:
            return "This is the generic name for the brand listed."
        case .brandNames:
            return "This is a brand name used for \(genericName)."
        case .indications:
            return "These are recognized indications for \(genericName)."
        case .adultDosage:
            return "This is a common adult dosing reference for \(genericName)."
        case .sideEffects:
            return "These are known side effects of \(genericName)."
        case .contraindications:
            return "These are contraindications associated with \(genericName)."
        case .interactions:
            return "These are relevant interactions for \(genericName)."
        case .pearls:
            return "These are practical clinical pearls for \(genericName)."
        }
    }
}
