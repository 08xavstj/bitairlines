import SwiftUI
import CoreCatalog
import CoreWorld

/// What the hangar shows: a search by maker or model, a certificate level, and whether it must fit an airport you use.
struct MarketFilter: Equatable {
    var query = ""
    /// 0 shows every level.
    var level = 0
    var fitsOnly = false

    func matches(_ type: AircraftType, fit: AircraftFit) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty && !type.displayName.lowercased().contains(q) && !type.id.contains(q) { return false }
        if level != 0 && type.level != level { return false }
        if fitsOnly && !fit.fitsAny { return false }
        return true
    }
}

/// The search field and the two choices above the list.
struct MarketFilterBar: View {
    @Binding var filter: MarketFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                PixelField(title: "Maker or model", text: $filter.query, prompt: "Cessna, Dash 8", capitalization: .never)
                PixelChoice(options: [(label: "All", value: false), (label: "Fits my airports", value: true)], selection: $filter.fitsOnly)
                    .frame(width: 260)
            }
            PixelChoice(options: [(label: "Any level", value: 0)] + (1...7).map { (label: "Level \($0)", value: $0) }, selection: $filter.level)
        }
    }
}
