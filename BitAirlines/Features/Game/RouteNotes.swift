import SwiftUI
import CoreCatalog
import CoreWorld

/// The service level choice for a route.
struct ServicePicker: View {
    let session: GameSession
    let route: Route

    var body: some View {
        HStack(spacing: 10) {
            Text("Service").pixelFont(10.667).foregroundStyle(Theme.textMuted)
            Spacer(minLength: 8)
            PixelChoice(options: ServiceLevel.allCases.map { (label: Words.name($0), value: $0) },
                        selection: Binding(get: { route.service }, set: { level in session.perform { try $0.setService(routeID: route.id, level: level) } }))
                .frame(maxWidth: 330)
        }
    }
}

/// Things worth knowing about a route: rivals on it, slots it is short of, people changing planes at a hub.
struct RouteNotes: View {
    let world: World
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rivalLines.enumerated()), id: \.offset) { _, line in
                Text(line).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(world.slotShortfall(route: route), id: \.airport) { item in
                Text("Needs \(item.needed) more daily slot\(item.needed == 1 ? "" : "s") at \(Place.name(item.airport)). Buy them in Bases, or flights wait a day.")
                    .pixelFont(10.667).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
            let through = route.legs.reduce(0.0) { $0 + $1.connectingPaxPerDay }
            if through > 0.5 {
                Text("About \(Int(through.rounded())) people a day could change planes at your hub on this route.")
                    .pixelFont(10.667).foregroundStyle(Theme.info).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rivalLines: [String] {
        var lines: [String] = []
        var seen: [String] = []
        for leg in route.legs {
            let key = [leg.from, leg.to].sorted().joined()
            guard !seen.contains(key) else { continue }
            seen.append(key)
            for rival in world.ops.rivals {
                for r in rival.routes where (r.a == leg.from && r.b == leg.to) || (r.a == leg.to && r.b == leg.from) {
                    lines += RivalWords.routeLines(rival: rival, route: r, from: leg.from, to: leg.to)
                }
            }
        }
        return lines
    }
}
