// CoreWorld/Registration.swift: aircraft registrations (tail numbers) in each country's style, for example C-FQXA or VH-TKB.
import CoreSim

public enum Registration {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func letters(_ count: Int, _ rng: inout SeededRandom) -> String {
        String((0..<count).map { _ in alphabet[rng.int(0...25)] })
    }

    /// A made-up registration in the style of the country (ISO code). Uniqueness is the caller's job (see World.nextRegistration).
    public static func make(country: String, rng: inout SeededRandom) -> String {
        switch country {
        case "CA": return "C-F" + letters(3, &rng)
        case "US": return "N" + String(rng.int(100...999)) + letters(2, &rng)
        case "AU": return "VH-" + letters(3, &rng)
        case "NZ": return "ZK-" + letters(3, &rng)
        case "GB": return "G-" + letters(4, &rng)
        case "DE": return "D-A" + letters(3, &rng)
        case "FR": return "F-G" + letters(3, &rng)
        case "NO": return "LN-" + letters(3, &rng)
        case "SE": return "SE-" + letters(3, &rng)
        case "FI": return "OH-" + letters(3, &rng)
        case "IS": return "TF-" + letters(3, &rng)
        case "GL", "DK": return "OY-" + letters(3, &rng)
        case "BR": return "PR-" + letters(3, &rng)
        case "AR": return "LV-" + letters(3, &rng)
        case "CL": return "CC-" + letters(3, &rng)
        case "PG": return "P2-" + letters(3, &rng)
        case "NP": return "9N-" + letters(3, &rng)
        case "RU": return "RA-" + String(rng.int(10000...99999))
        case "FJ": return "DQ-" + letters(3, &rng)
        case "VU": return "YJ-" + letters(3, &rng)
        default: return country + "-" + letters(3, &rng)
        }
    }
}
