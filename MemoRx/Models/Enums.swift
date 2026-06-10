import Foundation

enum Collection: String, Codable {
    case cardiology
    case infectiousDisease
    case endocrine
    case neuroPsych
    case pulmonary
    case gi
    case painInflammation
    case oncology
    case renalUrology
    case controlledSubstances
}

enum SubCollection: String, Codable {
    case aceInhibitors
    case arbs
    case betaBlockers
    case calciumChannelBlockers
    case statins
    case diuretics
    case penicillins
    case cephalosporins
    case macrolides
    case ssris
    case snris
    case tcAs
    case scheduleII   
    case scheduleIII
    case scheduleIV
    case scheduleV

}
