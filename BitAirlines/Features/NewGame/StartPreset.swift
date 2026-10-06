import CoreWorld

/// The one difficulty choice for a new airline. It sets both the rules (GameMode) and the starting money (Difficulty), which
/// used to be two separate pickers that looked like the same question.
enum StartPreset: String, CaseIterable {
    case relaxed, normal, hard, realism, sandbox

    var mode: GameMode {
        switch self {
        case .relaxed: .easy
        case .normal, .hard: .normal
        case .realism: .realism
        case .sandbox: .sandbox
        }
    }

    var difficulty: Difficulty {
        switch self {
        case .relaxed: .easy
        case .hard: .hard
        case .normal, .realism, .sandbox: .standard
        }
    }

    var label: String {
        switch self {
        case .relaxed: "Relaxed"
        case .normal: "Normal"
        case .hard: "Hard"
        case .realism: "Realism"
        case .sandbox: "Sandbox"
        }
    }

    var explain: String {
        switch self {
        case .relaxed: "More money to start. Any aircraft lands on any runway. No weather, no dark strips, no frozen lakes, no slots."
        case .normal: "Runway length and surface matter. Weather, daylight at small strips, lakes that freeze, slots at busy airports."
        case .hard: "Normal rules with less money to start, so the first aircraft has to pay its way."
        case .realism: "Normal, and fuel is only sold at real fuel stops. Plan chains of small strips or build fuel depots."
        case .sandbox: "Money never runs out and every certificate level is open. For building and painting."
        }
    }

    /// The preset that matches a draft's rules and money (Normal when they do not match one).
    static func of(mode: GameMode, difficulty: Difficulty) -> StartPreset {
        allCases.first { $0.mode == mode && $0.difficulty == difficulty } ?? .normal
    }
}
