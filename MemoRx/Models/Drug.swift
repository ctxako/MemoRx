import Foundation

struct DrugQuizQuestion: Codable {
    let question: String
    let options: [String]
    let correctAnswer: String
    let explanation: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case question, options, explanation, type
        case correctAnswer = "correct_answer"
    }
}

struct Drug: Codable, Identifiable {
    let id: String
    let genericName: String
    let brandNames: [String]
    let collection: DrugCollection
    let subCollection: SubCollection
    let drugClass: String
    let mechanismOfAction: String
    let indications: [String]
    let dosage: Dosage
    let sideEffects: [String]
    let warnings: [String]
    let contraindications: [String]
    let interactions: [String]
    let monitoring: [String]
    let counselingPoints: [String]
    let pearls: [String]
    let quizQuestions: [DrugQuizQuestion]?

    init(
        id: String,
        genericName: String,
        brandNames: [String],
        collection: DrugCollection,
        subCollection: SubCollection,
        drugClass: String,
        mechanismOfAction: String,
        indications: [String],
        dosage: Dosage,
        sideEffects: [String],
        warnings: [String],
        contraindications: [String],
        interactions: [String],
        monitoring: [String],
        counselingPoints: [String],
        pearls: [String],
        quizQuestions: [DrugQuizQuestion]? = nil
    ) {
        self.id = id
        self.genericName = genericName
        self.brandNames = brandNames
        self.collection = collection
        self.subCollection = subCollection
        self.drugClass = drugClass
        self.mechanismOfAction = mechanismOfAction
        self.indications = indications
        self.dosage = dosage
        self.sideEffects = sideEffects
        self.warnings = warnings
        self.contraindications = contraindications
        self.interactions = interactions
        self.monitoring = monitoring
        self.counselingPoints = counselingPoints
        self.pearls = pearls
        self.quizQuestions = quizQuestions
    }

    /// Stable grouping key for the global ordered library list (matches `DrugService` ordering).
    var classId: String { subCollection }

    /// Uppercased line for the front-of-card capsule.
    /// Uses specific pharmacologic class label (e.g. `ACE INHIBITOR`, `SSRI`).
    var cardFrontCollectionTag: String {
        drugClass.uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case genericName = "generic_name"
        case brandNames = "brand_names"
        case collection
        case subCollection = "sub_collection"
        case drugClass = "drug_class"
        case mechanismOfAction = "mechanism_of_action"
        case indications
        case dosage
        case sideEffects = "side_effects"
        case warnings
        case contraindications
        case interactions
        case monitoring
        case counselingPoints = "counseling_points"
        case pearls
        case quizQuestions = "quiz_questions"
    }
}
