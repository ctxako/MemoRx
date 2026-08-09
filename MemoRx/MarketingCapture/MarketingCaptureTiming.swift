import Foundation

/// All capture pacing in one place so the sequence can be tuned without touching
/// app behavior. Defaults target the ~33-second plan: 2.4s front + 0.5s flip +
/// 3.5s back + ~2.5s per question + 4.5s results + 2s final hold.
struct MarketingCaptureTiming: Sendable {
    var frontHold: TimeInterval = 2.4
    /// Matches DrugCardView's crossfade (0.22s fade-out + 0.26s fade-in).
    var flipDuration: TimeInterval = 0.5
    var backHold: TimeInterval = 3.5
    /// Per question: pause before the scripted option is selected.
    var answerSelectDelay: TimeInterval = 0.9
    /// Per question: pause between selection and submit.
    var submitDelay: TimeInterval = 0.5
    /// Per question: how long the answer/explanation reveal stays on screen.
    var revealHold: TimeInterval = 1.1
    /// How long the results screen (ring/XP animations) runs before completion is signaled.
    var resultsHold: TimeInterval = 4.5
    /// Clean ending frame for later editing.
    var finalHold: TimeInterval = 2.0

    static let standard = MarketingCaptureTiming()
}
