// CoreCatalog/StartRegions.swift: the places a new airline can start. All are remote or island regions where small aircraft rule.
// Text is ASCII (the pixel font has no accents) and written plainly.

public struct StartRegion: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let blurb: String
    /// Airports the player may pick as headquarters, the first being the classic choice.
    public let headquarters: [String]
}

public enum StartRegions {
    public static let all: [StartRegion] = [
        StartRegion(id: "arctic-canada", name: "Arctic Canada",
                    blurb: "Gravel strips on the Beaufort Sea and ice roads in winter. Freight is half the business.",
                    headquarters: ["YEV", "YCB", "YRT"]),
        StartRegion(id: "alaska", name: "Alaska Bush",
                    blurb: "More small airstrips than anywhere on Earth. Villages with no road at all.",
                    headquarters: ["BET", "OTZ", "DLG"]),
        StartRegion(id: "outback", name: "Australian Outback",
                    blurb: "Mining towns and cattle stations a day's drive apart, and the flying doctor.",
                    headquarters: ["ASP", "ISA", "BME"]),
        StartRegion(id: "png", name: "Papua New Guinea",
                    blurb: "Highland airstrips cut into mountainsides. No roads between most towns.",
                    headquarters: ["HGU", "GKA", "MAG"]),
        StartRegion(id: "himalaya", name: "Himalaya",
                    blurb: "Short, steep strips under the highest peaks. Brave pilots, thin air.",
                    headquarters: ["LUA", "JMO", "PHH"]),
        StartRegion(id: "greenland", name: "Greenland",
                    blurb: "A few big settlements on a huge coast, joined only by air and sea.",
                    headquarters: ["JAV", "GOH"]),
        StartRegion(id: "patagonia", name: "Patagonia",
                    blurb: "Wind, fjords and the end of the world. A gentler start with longer runways.",
                    headquarters: ["PUQ", "USH", "FTE"]),
        StartRegion(id: "melanesia", name: "Pacific Islands",
                    blurb: "Island hopping across blue water, with lagoons for floatplanes.",
                    headquarters: ["VLI", "HIR", "SUV"]),
        StartRegion(id: "amazon", name: "Amazon",
                    blurb: "River towns in the rainforest where a plane replaces a week by boat.",
                    headquarters: ["TBT", "RBR", "BVB"]),
        StartRegion(id: "caribbean", name: "Caribbean",
                    blurb: "Short hops between small islands, with tourists in season.",
                    headquarters: ["SXM", "ANU", "SKB"]),
    ]

    public static func region(_ id: String) -> StartRegion? { all.first { $0.id == id } }
}
