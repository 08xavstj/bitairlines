import SwiftUI
import CoreCatalog
import CoreWorld

/// Under an aircraft for sale: which of the airline's airports it can use, and what it needs for the others.
struct FitSummary: View {
    let fit: AircraftFit
    /// Airports listed one by one before the rest are counted.
    private let shown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline).pixelFont(10.667).foregroundStyle(fit.fitsAll ? Theme.good : (fit.fitsAny ? Theme.textPrimary : Theme.bad))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(fit.misfits.prefix(shown), id: \.code) { misfit in
                Text("\(Place.name(misfit.code)) needs " + FitWords.list(misfit.needs)).pixelFont(10.667).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if fit.misfits.count > shown {
                Text("and \(fit.misfits.count - shown) more").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var headline: String {
        let total = fit.airports.count
        if fit.fitsAll { return total == 1 ? "Fits your home airport" : "Fits all \(total) of your airports" }
        if !fit.fitsAny { return "Fits none of your airports" }
        let codes = fit.airports.filter(\.fits).map(\.code)
        return "Fits " + (codes.count <= shown ? Place.list(codes, separator: ", ") : "\(codes.count) of \(total) airports")
    }
}

/// The words for what an aircraft needs at an airport.
enum FitWords {
    static func name(_ need: FitNeed) -> String {
        switch need {
        case .floats: "floats"
        case .cannotUseWater: "floats, and none are made for this type"
        case .cannotUseRunway: "wheels, and this floatplane has none"
        case .gravelKit: "a gravel kit"
        case .paving: "a paved strip (base upgrade)"
        case .stolKit: "a STOL kit"
        case .runwayExtension: "a longer runway (base upgrade)"
        case .runwayTooShort(let ft): "\(Format.number(ft)) ft more runway than can be built"
        }
    }

    /// "a gravel kit and a STOL kit"
    static func list(_ needs: [FitNeed]) -> String {
        needs.map(name).joined(separator: " and ")
    }
}
