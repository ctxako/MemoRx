import Foundation
import SwiftUI

/// Owns the capture run: sessionless content loads, manifest load/generate,
/// phase sequencing, and terminal status for the accessibility marker.
///
/// loading -> card (front -> auto-flip -> back) -> quiz (scripted) -> finished
///                                            \-> failed(reason)
@MainActor
final class MarketingCaptureCoordinator: ObservableObject {
    enum Phase: Equatable {
        case loading
        case card
        case quiz
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var drug: Drug?
    private(set) var script: MarketingCaptureScript?
    let timing = MarketingCaptureTiming.standard

    private var started = false

    /// Terminal value for the `marketingCaptureStatus` accessibility marker.
    var statusMarkerValue: String? {
        switch phase {
        case .finished: return "finished"
        case .failed(let reason): return "failed:\(reason)"
        default: return nil
        }
    }

    var failureMessage: String? {
        if case .failed(let reason) = phase { return reason }
        return nil
    }

    func start() async {
        guard !started else { return }
        started = true

        guard SupabaseManager.isConfiguredForRemote else {
            phase = .failed("supabase-not-configured")
            return
        }

        // Sessionless content loads — DrugService / DailyChallengeService /
        // ClassQuizGuideService route to the anon-key paths under capture runtime.
        await DrugService.shared.loadFromSupabaseOnLaunch()
        await DailyChallengeService.shared.refreshFromServer()

        guard let assignment = DailyChallengeService.shared.assignment else {
            phase = .failed("no-server-assignment")
            return
        }
        guard isAcceptablyFresh(challengeDate: assignment.challengeDateRaw) else {
            phase = .failed("stale-assignment:\(assignment.challengeDateRaw)")
            return
        }

        await DailyChallengeService.shared.ensureCatalogContainsChallengeDrug()
        let catalog = DrugService.orderedDrugs.isEmpty ? DrugService.shared.drugs : DrugService.orderedDrugs
        guard let resolved = DailyChallengeService.shared.resolvedHighlightDrug(in: catalog) else {
            phase = .failed("drug-missing-from-catalog:\(assignment.drugId)")
            return
        }

        if ClassQuizGuideService.shared.guides.isEmpty {
            await ClassQuizGuideService.shared.loadFromSupabaseOnLaunch()
        }

        let manifest: MarketingCaptureManifest
        if let existing = MarketingCaptureManifest.load(
            challengeDate: assignment.challengeDateRaw, drugId: resolved.id
        ) {
            manifest = existing
        } else {
            switch buildManifest(challengeDate: assignment.challengeDateRaw, drug: resolved, catalog: catalog) {
            case .success(let built):
                manifest = built
            case .failure(let reason):
                phase = .failed(reason)
                return
            }
        }
        guard manifest.questions.count >= 4 else {
            phase = .failed("too-few-questions:\(manifest.questions.count)")
            return
        }

        drug = resolved
        script = MarketingCaptureScript(manifest: manifest, timing: timing)
        phase = .card

        // Card front is held by DrugCardView's auto-flip input; hand off to the
        // quiz after front + flip + back.
        try? await Task.sleep(
            nanoseconds: UInt64((timing.frontHold + timing.flipDuration + timing.backHold) * 1_000_000_000)
        )
        guard phase == .card else { return }
        phase = .quiz
    }

    /// Called by QuizView after its results reveal has run for `resultsHold`.
    func quizDidComplete() {
        guard phase == .quiz else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timing.finalHold * 1_000_000_000))
            guard phase == .quiz else { return }
            phase = .finished
        }
    }

    // MARK: - Manifest generation (mirrors QuizView.loadQuestions for .daily)

    private enum BuildResult {
        case success(MarketingCaptureManifest)
        case failure(String)
    }

    private func buildManifest(challengeDate: String, drug: Drug, catalog: [Drug]) -> BuildResult {
        var generated = QuizEngine.generateQuestions(for: drug, allDrugs: catalog)
        let targetDailyCount = generated.count + 1

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
            let engine = QuizEngine(drugs: catalog)
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

        guard let incorrectNumbers = MarketingCaptureManifest.incorrectQuestionNumbers(forCount: generated.count) else {
            return .failure("too-few-questions:\(generated.count)")
        }

        let snapshots = generated.map(MarketingCaptureQuestionSnapshot.init)
        let selections = snapshots.enumerated().map { index, snapshot in
            MarketingCaptureManifest.scriptedSelection(
                for: snapshot,
                isIncorrect: incorrectNumbers.contains(index + 1)
            )
        }

        let manifest = MarketingCaptureManifest(
            challengeDate: challengeDate,
            drugId: drug.id,
            createdAt: Date(),
            questions: snapshots,
            incorrectQuestionNumbers: incorrectNumbers,
            scriptedSelections: selections
        )
        do {
            try manifest.save()
        } catch {
            // Persistence failure only breaks retry determinism, not this run.
            #if DEBUG
            print("[MarketingCapture] manifest save failed: \(error)")
            #endif
        }
        return .success(manifest)
    }

    private func isAcceptablyFresh(challengeDate raw: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        guard let serverDay = formatter.date(from: raw) else { return false }
        let today = formatter.date(from: formatter.string(from: Date())) ?? Date()
        // ±1 day tolerance for server/device timezone skew; anything further is stale.
        return abs(serverDay.timeIntervalSince(today)) <= 86_400
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func questionSignature(_ question: QuizQuestion) -> String {
        let answers = question.correctAnswers.map(normalized).sorted().joined(separator: "|")
        return "\(normalized(question.question))::\(answers)"
    }
}
