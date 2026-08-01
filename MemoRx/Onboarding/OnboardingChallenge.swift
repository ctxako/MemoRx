import Foundation

/// A question the user got wrong, carried from the challenge screen to the result
/// screen. Holds both the drug (so its monitoring profile can be shown) and the
/// specific correct answer the user failed to pick (featured at the top of the card).
struct OnboardingMiss: Identifiable {
    let drugGenericName: String
    let missedAnswer: String
    var id: String { drugGenericName }
}

/// Hardcoded onboarding diagnostic challenge — a fixed 3-question set, deliberately
/// NOT drawn from the spaced-repetition `QuizEngine`. Each item pairs a reusable
/// `QuizQuestion` (the same model the main quiz uses) with the generic name of the
/// drug it maps to, so `ResultGapStepView` can resolve that drug from `DrugService`
/// and render its real `monitoring` data as the "gap" card.
///
/// The explanations here are concise question rationale for the in-quiz reveal; the
/// deeper "gap" content on the result screen comes from `Drug.monitoring`, never
/// hand-written into the view.
enum OnboardingChallenge {
    struct Item {
        let question: QuizQuestion
        /// Lowercased `generic_name` used to look the drug up in `DrugService`.
        let drugGenericName: String
    }

    static let items: [Item] = [
        Item(
            question: QuizQuestion(
                id: UUID(),
                drugId: "warfarin",
                question: "A patient is started on warfarin for atrial fibrillation. Which lab value should be monitored to guide dosing?",
                options: ["INR", "aPTT", "Platelet count", "Anti-Xa level"],
                correctAnswers: ["INR"],
                isMultiSelect: false,
                explanation: "Warfarin is dosed to a target INR (typically 2–3 in atrial fibrillation). aPTT tracks heparin, and anti-Xa tracks LMWH/DOACs — not warfarin."
            ),
            drugGenericName: "warfarin"
        ),
        Item(
            question: QuizQuestion(
                id: UUID(),
                drugId: "digoxin",
                question: "What is the target serum digoxin level for a patient with heart failure?",
                options: ["0.5–0.9 ng/mL", "1.5–2.5 ng/mL", "4–12 mcg/mL", "10–20 mcg/mL"],
                correctAnswers: ["0.5–0.9 ng/mL"],
                isMultiSelect: false,
                explanation: "In heart failure, a lower serum digoxin target of 0.5–0.9 ng/mL balances benefit against toxicity risk. The mcg/mL ranges are distractors from other drugs."
            ),
            drugGenericName: "digoxin"
        ),
        Item(
            question: QuizQuestion(
                id: UUID(),
                drugId: "lithium",
                question: "When should a trough lithium level be drawn?",
                options: [
                    "~12 hours after the dose",
                    "30 minutes after the dose",
                    "Immediately before the morning dose, regardless of timing",
                    "4 hours after the dose"
                ],
                correctAnswers: ["~12 hours after the dose"],
                isMultiSelect: false,
                explanation: "Lithium troughs are drawn ~12 hours after the last dose so levels are comparable and can be used to adjust dosing safely."
            ),
            drugGenericName: "lithium"
        )
    ]
}
