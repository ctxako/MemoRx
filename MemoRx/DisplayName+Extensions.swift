import Foundation

extension SubCollection {
    var displayName: String {
        switch self {
        case .aceInhibitors: return "ACE Inhibitors"
        case .arbs: return "ARBs"
        case .betaBlockers: return "Beta Blockers"
        case .calciumChannelBlockers: return "Calcium Channel Blockers"
        case .statins: return "Statins"
        case .diuretics: return "Diuretics"
        case .penicillins: return "Penicillins"
        case .cephalosporins: return "Cephalosporins"
        case .macrolides: return "Macrolides"
        case .ssris: return "SSRIs"
        case .snris: return "SNRIs"
        case .tcAs: return "Tricyclic Antidepressants"
        case .scheduleII: return "Schedule II"
        case .scheduleIII: return "Schedule III"
        case .scheduleIV: return "Schedule IV"
        case .scheduleV: return "Schedule V"
        }
    }
}

extension Collection {
    var displayName: String {
        switch self {
        case .cardiology: return "Cardiology"
        case .infectiousDisease: return "Infectious Disease"
        case .endocrine: return "Endocrine"
        case .neuroPsych: return "Neuro & Psych"
        case .pulmonary: return "Pulmonary"
        case .gi: return "GI"
        case .painInflammation: return "Pain & Inflammation"
        case .oncology: return "Oncology"
        case .renalUrology: return "Renal & Urology"
        case .controlledSubstances: return "Controlled Substances"
        }
    }
}
