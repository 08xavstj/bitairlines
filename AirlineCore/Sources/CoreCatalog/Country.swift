// CoreCatalog/Country.swift: countries and the world region groups the game uses for unlocks and start locations.

public enum RegionGroup: String, Sendable, Hashable, Codable, CaseIterable {
    case northAmerica = "NAM", centralAmerica = "CAM", caribbean = "CAR", southAmerica = "SAM"
    case europeWest = "EUW", europeEast = "EUE", nordics = "NRD", russia = "RUS"
    case middleEast = "MEA", northAfrica = "NAF", centralAsia = "CAS", southAsia = "SAS"
    case eastAsia = "EAS", southeastAsia = "SEA", oceania = "OCE", subSaharanAfrica = "SSA"

    /// ASCII only: the pixel font has no accents.
    public var displayName: String {
        switch self {
        case .northAmerica: "North America"
        case .centralAmerica: "Central America"
        case .caribbean: "Caribbean"
        case .southAmerica: "South America"
        case .europeWest: "Western Europe"
        case .europeEast: "Eastern Europe"
        case .nordics: "Nordics"
        case .russia: "Russia"
        case .middleEast: "Middle East"
        case .northAfrica: "North Africa"
        case .centralAsia: "Central Asia"
        case .southAsia: "South Asia"
        case .eastAsia: "East Asia"
        case .southeastAsia: "Southeast Asia"
        case .oceania: "Oceania"
        case .subSaharanAfrica: "Sub-Saharan Africa"
        }
    }
}

public struct Country: Sendable, Hashable, Identifiable {
    /// ISO 3166 alpha-2 code.
    public let code: String
    public let name: String
    public let group: RegionGroup
    /// Wealth tier 1 (low) to 5 (very high): scales how much people fly and what they will pay.
    public let wealth: Int
    public var id: String { code }
}

extension Country {
    /// Parses one generated row: code|name|group|wealth
    init?(row: Substring) {
        let f = row.split(separator: "|", omittingEmptySubsequences: false)
        guard f.count == 4, let group = RegionGroup(rawValue: String(f[2])), let wealth = Int(f[3]) else { return nil }
        self.init(code: String(f[0]), name: String(f[1]), group: group, wealth: wealth)
    }
}

public enum CountryCatalog {
    public static let all: [Country] = CountryRows.rows.split(separator: "\n").compactMap { Country(row: $0) }

    public static let byCode: [String: Country] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func country(_ code: String) -> Country? { byCode[code] }
}
