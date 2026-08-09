import Foundation

/// Codable mirror of `QuizQuestion` so manifest persistence is decoupled from the
/// engine model — retries stay deterministic across engine changes.
struct MarketingCaptureQuestionSnapshot: Codable, Equatable, Sendable {
    var drugId: String
    var question: String
    var options: [String]
    var correctAnswers: [String]
    var isMultiSelect: Bool
    var explanation: String

    init(_ q: QuizQuestion) {
        drugId = q.drugId
        question = q.question
        options = q.options
        correctAnswers = q.correctAnswers
        isMultiSelect = q.isMultiSelect
        explanation = q.explanation
    }

    func toQuizQuestion() -> QuizQuestion {
        QuizQuestion(
            id: UUID(),
            drugId: drugId,
            question: question,
            options: options,
            correctAnswers: correctAnswers,
            isMultiSelect: isMultiSelect,
            explanation: explanation
        )
    }
}

/// Local-only retry manifest for one date/drug capture. Contains no credentials
/// or learner data. A retry reloads this file and reproduces the identical quiz.
struct MarketingCaptureManifest: Codable, Equatable {
    var challengeDate: String
    var drugId: String
    var createdAt: Date
    var questions: [MarketingCaptureQuestionSnapshot]
    /// 1-based question numbers answered incorrectly (fixed rule, see `incorrectQuestionNumbers(forCount:)`).
    var incorrectQuestionNumbers: [Int]
    /// Scripted selections per question, aligned to `questions`.
    var scriptedSelections: [[String]]

    /// Strong-but-not-perfect score with wrong answers distributed mid-quiz:
    /// 7–8 questions → wrong at 3 and 6 (6/8 = 75%, 5/7 = 71%);
    /// 4–6 questions (degraded fallback) → wrong at 3 only.
    /// Below 4, the run must fail — returns nil.
    static func incorrectQuestionNumbers(forCount count: Int) -> [Int]? {
        if count >= 7 { return [3, 6] }
        if count >= 4 { return [3] }
        return nil
    }

    /// Deterministic selection for one question: the correct answers, or for a
    /// scripted miss the first wrong option (single-select) / first correct +
    /// first wrong option (multi-select, which still fails the exact-set check).
    static func scriptedSelection(
        for snapshot: MarketingCaptureQuestionSnapshot,
        isIncorrect: Bool
    ) -> [String] {
        guard isIncorrect else { return snapshot.correctAnswers }
        let wrongOptions = snapshot.options.filter { !snapshot.correctAnswers.contains($0) }
        guard let firstWrong = wrongOptions.first else { return snapshot.correctAnswers }
        if snapshot.isMultiSelect {
            guard let firstCorrect = snapshot.correctAnswers.first else { return [firstWrong] }
            return [firstCorrect, firstWrong]
        }
        return [firstWrong]
    }

    // MARK: - Persistence (Documents/MarketingCapture/)

    private static func directoryURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent("MarketingCapture", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(challengeDate: String, drugId: String) throws -> URL {
        let safeDrug = drugId.replacingOccurrences(of: "/", with: "_")
        return try directoryURL().appendingPathComponent("manifest-\(challengeDate)-\(safeDrug).json")
    }

    static func load(challengeDate: String, drugId: String) -> MarketingCaptureManifest? {
        guard let url = try? fileURL(challengeDate: challengeDate, drugId: drugId),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MarketingCaptureManifest.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let url = try Self.fileURL(challengeDate: challengeDate, drugId: drugId)
        try data.write(to: url, options: .atomic)
    }
}

/// Runtime script handed to `QuizView` in capture mode: immutable questions,
/// scripted selections, and pacing. Built from the manifest, never regenerated.
struct MarketingCaptureScript {
    let questions: [QuizQuestion]
    /// Aligned to `questions`.
    let selections: [[String]]
    let timing: MarketingCaptureTiming

    init(manifest: MarketingCaptureManifest, timing: MarketingCaptureTiming) {
        questions = manifest.questions.map { $0.toQuizQuestion() }
        selections = manifest.scriptedSelections
        self.timing = timing
    }
}
