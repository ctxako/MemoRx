import Foundation

typealias DrugCollection = String
typealias SubCollection = String

enum KnownCollection {
    static let cardiology = "cardiology"
    static let controlledSubstances = "controlledSubstances"
    static let endocrinology = "endocrinology"
    static let psychiatry = "psychiatry"
    static let neurology = "neurology"
    static let urology = "urology"
    static let neuroPsych = "neuroPsych"
    static let rheumatology = "rheumatology"
    static let oncology = "oncology"
    static let respiratory = "respiratory"
    static let infectiousDisease = "infectiousDisease"
    static let anesthesiology = "anesthesiology"
    static let gastroenterology = "gastroenterology"

    static let displayNames: [String: String] = [
        cardiology: "Cardiology",
        controlledSubstances: "Controlled Substances",
        endocrinology: "Endocrinology",
        psychiatry: "Psychiatry",
        neurology: "Neurology",
        urology: "Urology",
        neuroPsych: "Neuro/Psych",
        rheumatology: "Rheumatology",
        oncology: "Oncology",
        respiratory: "Respiratory",
        infectiousDisease: "Infectious Disease",
        anesthesiology: "Anesthesiology",
        gastroenterology: "Gastroenterology",
    ]
}

enum KnownSubCollection {
    static let aceInhibitors = "aceInhibitors"
    static let alpha1Blockers = "alpha1Blockers"
    static let alzheimersAgents = "alzheimersAgents"
    static let angiotensinReceptorBlockers = "angiotensinReceptorBlockers"
    static let antiarrhythmics = "antiarrhythmics"
    static let anticoagulants = "anticoagulants"
    static let anticonvulsants = "anticonvulsants"
    static let antidepressants = "antidepressants"
    static let antiepileptics = "antiepileptics"
    static let antimetabolites = "antimetabolites"
    static let antiplatelets = "antiplatelets"
    static let antivirals = "antivirals"
    static let arbThiazideCombinations = "arbThiazideCombinations"
    static let aromataseInhibitors = "aromataseInhibitors"
    static let atypicalAntipsychotics = "atypicalAntipsychotics"
    static let betaBlockers = "betaBlockers"
    static let biguanides = "biguanides"
    static let bisphosphonates = "bisphosphonates"
    static let calciumChannelBlockers = "calciumChannelBlockers"
    static let dopamineAgonists = "dopamineAgonists"
    static let dpp4BiguanideCombinations = "dpp4BiguanideCombinations"
    static let fiveAlphaReductaseInhibitors = "5AlphaReductaseInhibitors"
    static let fibrates = "fibrates"
    static let glp1ReceptorAgonists = "glp1ReceptorAgonists"
    static let goutAgents = "goutAgents"
    static let icsLabaCombinations = "icsLabaCombinations"
    static let insulins = "insulins"
    static let intranasalCorticosteroids = "intranasalCorticosteroids"
    static let localAnesthetics = "localAnesthetics"
    static let loopDiuretics = "loopDiuretics"
    static let muscleRelaxants = "muscleRelaxants"
    static let nitrates = "nitrates"
    static let norepinephrineDopamineReuptakeInhibitors = "norepinephrineDopamineReuptakeInhibitors"
    static let nsaids = "nsaids"
    static let pde5Inhibitors = "pde5Inhibitors"
    static let potassiumSparingDiuretics = "potassiumSparingDiuretics"
    static let protonPumpInhibitors = "protonPumpInhibitors"
    static let scheduleII = "scheduleII"
    static let scheduleIII = "scheduleIII"
    static let scheduleIV = "scheduleIV"
    static let scheduleV = "scheduleV"
    static let serotoninModulators = "serotoninModulators"
    static let sglt2Inhibitors = "sglt2Inhibitors"
    static let shortActingBetaAgonists = "shortActingBetaAgonists"
    static let snris = "snris"
    static let ssris = "ssris"
    static let statins = "statins"
    static let sulfonylureas = "sulfonylureas"
    static let thiazideDiuretics = "thiazideDiuretics"
    static let thyroidHormones = "thyroidHormones"
    static let topicalAntibiotics = "topicalAntibiotics"
    static let tricyclicAntidepressants = "tricyclicAntidepressants"
    static let triptans = "triptans"
    static let vegfInhibitors = "vegfInhibitors"
    static let vestibularSuppressants = "vestibularSuppressants"

    static let displayNames: [String: String] = [
        "5AlphaReductaseInhibitors": "5-Alpha Reductase Inhibitors",
        aceInhibitors: "ACE Inhibitors",
        alpha1Blockers: "Alpha-1 Blockers",
        alzheimersAgents: "Alzheimer's Agents",
        angiotensinReceptorBlockers: "Angiotensin Receptor Blockers (ARBs)",
        antiarrhythmics: "Antiarrhythmics",
        anticoagulants: "Anticoagulants",
        anticonvulsants: "Anticonvulsants",
        antidepressants: "Antidepressants",
        antiepileptics: "Antiepileptics",
        antimetabolites: "Antimetabolites",
        antiplatelets: "Antiplatelets",
        antivirals: "Antivirals",
        arbThiazideCombinations: "ARB/Thiazide Combinations",
        aromataseInhibitors: "Aromatase Inhibitors",
        atypicalAntipsychotics: "Atypical Antipsychotics",
        betaBlockers: "Beta Blockers",
        biguanides: "Biguanides",
        bisphosphonates: "Bisphosphonates",
        calciumChannelBlockers: "Calcium Channel Blockers",
        dopamineAgonists: "Dopamine Agonists",
        dpp4BiguanideCombinations: "DPP-4/Biguanide Combinations",
        fibrates: "Fibrates",
        glp1ReceptorAgonists: "GLP-1 Receptor Agonists",
        goutAgents: "Gout Agents",
        icsLabaCombinations: "ICS/LABA Combinations",
        insulins: "Insulins",
        intranasalCorticosteroids: "Intranasal Corticosteroids",
        localAnesthetics: "Local Anesthetics",
        loopDiuretics: "Loop Diuretics",
        muscleRelaxants: "Muscle Relaxants",
        nitrates: "Nitrates",
        norepinephrineDopamineReuptakeInhibitors: "Norepinephrine-Dopamine Reuptake Inhibitors (NDRIs)",
        nsaids: "NSAIDs",
        pde5Inhibitors: "PDE5 Inhibitors",
        potassiumSparingDiuretics: "Potassium-Sparing Diuretics",
        protonPumpInhibitors: "Proton Pump Inhibitors",
        scheduleII: "Schedule II",
        scheduleIII: "Schedule III",
        scheduleIV: "Schedule IV",
        scheduleV: "Schedule V",
        serotoninModulators: "Serotonin Modulators",
        sglt2Inhibitors: "SGLT2 Inhibitors",
        shortActingBetaAgonists: "Short-Acting Beta Agonists",
        snris: "SNRIs",
        ssris: "SSRIs",
        statins: "Statins",
        sulfonylureas: "Sulfonylureas",
        thiazideDiuretics: "Thiazide Diuretics",
        thyroidHormones: "Thyroid Hormones",
        topicalAntibiotics: "Topical Antibiotics",
        tricyclicAntidepressants: "Tricyclic Antidepressants",
        triptans: "Triptans",
        vegfInhibitors: "VEGF Inhibitors",
        vestibularSuppressants: "Vestibular Suppressants",
    ]

    static let preferredOrder: [String] = [
        aceInhibitors, alpha1Blockers, angiotensinReceptorBlockers,
        arbThiazideCombinations, betaBlockers, calciumChannelBlockers,
        anticoagulants, antiplatelets, antiarrhythmics, nitrates,
        loopDiuretics, thiazideDiuretics, potassiumSparingDiuretics,
        statins, fibrates,
        biguanides, sulfonylureas, insulins,
        sglt2Inhibitors, glp1ReceptorAgonists, dpp4BiguanideCombinations,
        thyroidHormones,
        ssris, snris, tricyclicAntidepressants, serotoninModulators,
        norepinephrineDopamineReuptakeInhibitors, antidepressants,
        atypicalAntipsychotics,
        anticonvulsants, antiepileptics, dopamineAgonists, alzheimersAgents,
        triptans, vestibularSuppressants,
        nsaids, goutAgents, muscleRelaxants, bisphosphonates,
        protonPumpInhibitors,
        shortActingBetaAgonists, icsLabaCombinations, intranasalCorticosteroids,
        antivirals, topicalAntibiotics,
        localAnesthetics,
        pde5Inhibitors, fiveAlphaReductaseInhibitors,
        antimetabolites, aromataseInhibitors, vegfInhibitors,
        scheduleII, scheduleIII, scheduleIV, scheduleV,
    ]

    static let colors: [String: String] = [
        "ACE Inhibitors": "3DBFBF",
        "Beta Blockers": "5B8FF9",
        "SSRIs": "8B72BE",
        "Schedule II": "2C2C2C",
        "Schedule III": "444444",
        "Schedule IV": "5E5E5E",
        "Schedule V": "787878",
    ]
}

private func formatCamelCaseKey(_ key: String) -> String {
    key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
       .replacingOccurrences(of: "([0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
       .replacingOccurrences(of: "([a-zA-Z])([0-9])", with: "$1 $2", options: .regularExpression)
       .localizedCapitalized
}

func subCollectionDisplayName(_ key: String) -> String {
    KnownSubCollection.displayNames[key] ?? formatCamelCaseKey(key)
}

func collectionDisplayName(_ key: String) -> String {
    KnownCollection.displayNames[key] ?? formatCamelCaseKey(key)
}
