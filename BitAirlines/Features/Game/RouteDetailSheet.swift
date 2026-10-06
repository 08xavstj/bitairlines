import SwiftUI
import CoreWorld

/// Everything about one route: schedule, fare, aircraft, outlook and each leg. Opened from a row in the routes list.
struct RouteDetailSheet: View {
    let session: GameSession
    let routeID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var selling = false
    @State private var assigning = false

    var body: some View {
        let world = session.world
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Route") { Button("Close") { dismiss() }.buttonStyle(.small) }
            if let notice = session.notice {
                Text(notice).pixelFont(10.667).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
            }
            if let route = world.routes.first(where: { $0.id == routeID }) {
                ScrollView {
                    RouteCard(session: session, route: route, onDelete: { deleting = true }, onSell: { selling = true }, onAddAircraft: { assigning = true })
                }
            } else {
                EmptyNote("This route is closed.")
                Spacer()
            }
        }
        .padding(16)
        .screenBackground()
        .onAppear { session.notice = nil }
        .pixelConfirm("Close this route?", message: "Its aircraft are parked. Money already earned is kept.", confirm: "Close route", destructive: true,
                      isPresented: $deleting) {
            if session.perform({ try $0.deleteRoute(id: routeID) }) { dismiss() }
        }
        .pixelConfirm("Sell this route?", message: GrowthWords.sellRoute(price: world.routeSalePrice(routeID: routeID)), confirm: "Sell route", destructive: true,
                      isPresented: $selling) {
            if session.perform(sound: .coin, { _ = try $0.sellRoute(routeID: routeID) }) { dismiss() }
        }
        .sheet(isPresented: $assigning) { RouteAssignSheet(session: session, routeID: routeID) }
        // A stopping issue is drawn under any sheet: close this one so the player sees it.
        .onChange(of: session.world.isPausedByIssue) { _, now in if now { dismiss() } }
    }
}
