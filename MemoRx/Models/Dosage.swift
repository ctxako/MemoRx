import Foundation

struct Dosage: Codable {
    let adult: String
    let renalAdjustment: String
    let maxDose: String

    enum CodingKeys: String, CodingKey {
        case adult
        case renalAdjustment = "renal_adjustment"
        case maxDose = "max_dose"
    }
}
