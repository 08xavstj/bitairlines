import CoreWorld

/// The few facts about a world that decide which sounds to play. Small, so the game can compare it on every tick.
struct WorldHeard: Equatable {
    var newsCount: Int
    var newsLast: NewsItem?
    var issueIDs: Set<Int>
    var bankrupt: Bool

    init(_ world: World) {
        newsCount = world.news.count
        newsLast = world.news.last
        issueIDs = Set(world.issues.map(\.id))
        bankrupt = world.isBankrupt
    }
}

/// Turns what happened in the world into sounds. Buying and selling are heard when the player does them (see `GameSession.perform`),
/// so only the things the world does by itself, or as a result, are covered here.
enum SoundCues {
    /// The sounds for whatever changed since the player last heard the world (nothing if nothing did).
    static func between(_ old: WorldHeard, and world: World) -> [SoundEffect] {
        var cues: [SoundEffect] = []
        if !old.bankrupt && world.isBankrupt { cues.append(.gameOver) }
        for issue in world.issues where !old.issueIDs.contains(issue.id) { cues.append(issue.isCritical || issue.pausesGame ? .alarm : .notice) }
        if world.news.last != old.newsLast || world.news.count != old.newsCount {
            for item in world.news.reversed() {
                if item == old.newsLast { break }
                if let cue = cue(for: item) { cues.append(cue) }
            }
        }
        return cues
    }

    /// The sound for one news line. A milestone is a celebration, except an aircraft giving up its job or its empty flight
    /// ("jobgone:" and "ferrygone:" subjects), which is something to look at.
    static func cue(for item: NewsItem) -> SoundEffect? {
        if item.kind == .milestone && (item.subject.hasPrefix("ferrygone:") || item.subject.hasPrefix("jobgone:")) { return .notice }
        return cue(for: item.kind)
    }

    static func cue(for kind: NewsItem.Kind) -> SoundEffect? {
        switch kind {
        case .routeOpened: .routeOpened
        case .aircraftDelivered: .arrival
        case .certificate, .milestone, .scenario: .levelUp
        case .weather, .event, .rivalRoute, .pilotSick, .jobLate, .noCrew: .notice
        case .jobDone: .coin
        case .aircraftSold, .breakdown, .loan, .permit, .perk, .fuelBought, .baseBuilt, .kitFitted, .slotBought, .pilotHired, .growth, .fleetMoved: nil
        }
    }
}
