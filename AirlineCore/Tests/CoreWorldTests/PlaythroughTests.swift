import Testing
import CoreCatalog
@testable import CoreWorld

/// A simple bot plays whole games the way a careful player would: it opens the best suggested routes (buying the slots a busy
/// airport hands out), buys aircraft for them, takes jobs with idle aircraft, answers every issue, takes perks and the next
/// certificate. It pulls the reputation levers too: quick repairs when the bank allows, a hangar at home for quicker checks, and,
/// once only reputation stands between it and the next level, campaigns and premium service on full routes.
/// After every game day it checks that the world still holds together. The PLAYTEST lines in the log show how far each start got.
@Suite struct PlaythroughTests {
    /// A finished game: the world, anything that broke, and the day each new certificate level was bought.
    struct Playthrough {
        var world: World
        var problems: [String]
        var levels: [(level: Int, day: Int)]
        /// Level, reputation and lifetime revenue after one game year.
        var yearOne: (level: Int, reputation: Double, revenue: Int)?
    }

    /// Cash the bot keeps back when it spends on slots, campaigns and repairs.
    static let reserve = 400_000

    /// The first starter aircraft whose best suggested route earns the most, so the bot starts like a player would.
    func newGame(home: String, seed: UInt64) throws -> World? {
        var best: (world: World, profit: Double)?
        for offer in World.starterOffers(home: home, difficulty: .standard) {
            let config = NewGameConfig(airlineName: "Bot Air", airlineCode: "BT", homeAirport: home, branding: .starter,
                                       difficulty: .standard, starterTypeID: offer.typeID, seed: seed, mode: .normal)
            guard let w = try? World.newGame(config) else { continue }
            let profit = w.routeIdeas(limit: 1).first?.profitPerDay ?? -1
            if best == nil || profit > best!.profit { best = (w, profit) }
        }
        return best?.world
    }

    /// Everything that must always be true between game days.
    func problems(_ w: World) -> [String] {
        var found: [String] = []
        for route in w.routes {
            for id in route.aircraftIDs {
                guard let plane = w.aircraft.first(where: { $0.id == id }) else { found.append("route \(route.id) lists missing aircraft \(id)"); continue }
                if !plane.allRouteIDs.contains(route.id) { found.append("route \(route.id) lists \(plane.registration), which does not fly it") }
            }
            if Set(route.aircraftIDs).count != route.aircraftIDs.count { found.append("route \(route.id) lists an aircraft twice") }
        }
        for plane in w.aircraft {
            for rid in plane.allRouteIDs {
                guard let route = w.routes.first(where: { $0.id == rid }) else { found.append("\(plane.registration) flies missing route \(rid)"); continue }
                if !route.aircraftIDs.contains(plane.id) { found.append("\(plane.registration) flies route \(rid), which does not list it") }
            }
            if let t = plane.eventMinute, t < w.clock.minute, !w.isPausedByIssue { found.append("\(plane.registration) has an event in the past (\(t) < \(w.clock.minute))") }
            if let jid = plane.jobID, !w.ops.jobs.contains(where: { $0.id == jid && $0.aircraftID == plane.id }) {
                found.append("\(plane.registration) is on job \(jid), which does not name it")
            }
            if plane.condition.isNaN || plane.condition < 0 || plane.condition > 100 { found.append("\(plane.registration) condition \(plane.condition)") }
        }
        for job in w.ops.jobs {
            if let pid = job.aircraftID, w.aircraft.first(where: { $0.id == pid })?.jobID != job.id { found.append("job \(job.id) names aircraft \(pid), which is not on it") }
        }
        return found
    }

    /// The bot's weekly decisions.
    func decide(_ w: inout World) {
        if !w.ops.perkChoices.isEmpty, let perk = w.ops.perkChoices.first { try? w.choosePerk(perk) }
        if w.canUpgradeCertificate { try? w.upgradeCertificate() }
        let focus: RouteIdeaFocus = w.airline.level >= 2 ? .biggerCities : .smallStrips
        let ideas = w.routeIdeas(limit: 4, focus: focus) + (focus == .biggerCities ? w.routeIdeas(limit: 2) : [])
        // Idle aircraft: give each a route of its own type. An idea whose slots the bank cannot pay for yet waits.
        for plane in w.aircraft where plane.isDelivered && plane.allRouteIDs.isEmpty && plane.jobID == nil {
            let cash = w.airline.cash
            guard let idea = ideas.first(where: { $0.typeID == plane.typeID && $0.rankValue > 0 && canPaySlots($0, cash: cash) }) else { continue }
            let existing = w.routes.first { Set($0.stops) == Set(idea.stops) }?.id
            let routeID = existing ?? (try? w.createRoute(stops: idea.stops))
            if let routeID { try? w.assign(aircraftID: plane.id, toRoute: routeID) }
        }
        buyMissingSlots(&w)
        // With money to spare, buy a used aircraft for the best idea that needs one (and the slots it needs).
        if w.aircraft.count < 14, let idea = ideas.first(where: { $0.rankValue > 500 }),
           let listing = w.market.listings.filter({ $0.typeID == idea.typeID }).min(by: { $0.price < $1.price }),
           w.airline.cash > listing.price + idea.slotCost + Self.reserve {
            _ = try? w.buyUsed(listingID: listing.id)
        }
        // Idle aircraft fly jobs they can take.
        for job in w.ops.jobs where !job.isTaken {
            if let plane = w.aircraft.first(where: { $0.allRouteIDs.isEmpty && $0.jobID == nil && w.jobProblem(jobID: job.id, aircraftID: $0.id) == nil }) {
                try? w.takeJob(jobID: job.id, aircraftID: plane.id)
            }
        }
        if w.airline.level >= 2 && !w.hasStaff(.fleetPlanner) && w.airline.cash > 2_000_000 { try? w.hire(.fleetPlanner) }
        workOnReputation(&w)
    }

    /// True when the idea needs no slots, or the bank can pay for them and keep its reserve.
    func canPaySlots(_ idea: RouteIdea, cash: Int) -> Bool {
        idea.slotCost == 0 || cash > idea.slotCost + Self.reserve
    }

    /// Buys the daily slots a route is short of at busy airports, when the bank can pay and keep its reserve.
    func buyMissingSlots(_ w: inout World) {
        for route in w.routes {
            for need in w.slotNeeds(route: route) where w.airline.cash > need.cost + Self.reserve {
                try? w.buySlots(at: need.airport, count: need.slots)
            }
        }
    }

    /// The reputation levers a careful player pulls. A hangar at home once the bank is comfortable (checks take half the time,
    /// so routes miss fewer departures). When only reputation stands between the airline and its next level: a radio campaign,
    /// a national one when the bank allows, and premium service on routes whose seats are mostly full and that make money.
    func workOnReputation(_ w: inout World) {
        let home = w.airline.home
        if w.airline.level >= 2, !w.hasHangar(at: home), let airport = AirportCatalog.airport(home),
           w.airline.cash > w.facilityPrice(.hangar, at: airport) + 2_000_000 {
            try? w.build(.hangar, at: home)
        }
        guard let next = w.nextLevelRequirement, w.airline.reputation < next.reputation,
              w.airline.stats.revenue >= next.lifetimeRevenue else { return }
        for campaign in [Campaign.radio, Campaign.national] where w.campaignProblem(campaign) == nil {
            if w.airline.cash > 4 * w.campaignPrice(campaign) + Self.reserve { try? w.startCampaign(campaign) }
        }
        for route in w.routes where route.service != .premium {
            let recent = route.book.recent
            let full = recent.seats > 0 && Double(recent.passengers) >= 0.8 * Double(recent.seats)
            if full && recent.revenue > recent.flightCost + recent.aircraftCost { try? w.setService(routeID: route.id, level: .premium) }
        }
    }

    /// Answers every issue that stops the game. A breakdown is repaired the quickest way the bank can pay for with its reserve
    /// kept (every day the aircraft stands, its route may miss departures); otherwise the cheapest choice the airline can pay for.
    func answerIssues(_ w: inout World) {
        for _ in 0..<20 where w.isPausedByIssue {
            guard let issue = w.issues.first(where: { $0.pausesGame }) else { return }
            let cash = w.airline.cash
            let affordable = issue.options.filter { $0.costUSD <= max(0, cash) }
            var pick = affordable.min { ($0.costUSD, $0.days) < ($1.costUSD, $1.days) } ?? issue.options.last
            if case .breakdown = issue.kind,
               let quick = issue.options.filter({ $0.costUSD + Self.reserve <= cash }).min(by: { ($0.days, $0.costUSD) < ($1.days, $1.costUSD) }) {
                pick = quick
            }
            guard let choice = pick?.choice else { return }
            if (try? w.resolve(issueID: issue.id, choice: choice)) == nil {
                // Nothing it offers can be taken: drop the notice so the bot carries on, and say so.
                print("PLAYTEST could not answer issue \(issue.kind) at day \(w.clock.dayIndex)")
                return
            }
        }
    }

    func play(home: String, days: Int, seed: UInt64) throws -> Playthrough {
        guard var w = try newGame(home: home, seed: seed) else {
            return Playthrough(world: try Fixtures.world(), problems: ["no starter aircraft can use \(home)"], levels: [], yearOne: nil)
        }
        var problems: [String] = []
        var levels: [(level: Int, day: Int)] = []
        var yearOne: (level: Int, reputation: Double, revenue: Int)?
        for day in 0..<days {
            if day % 7 == 0 { decide(&w) }
            let target = (w.clock.dayIndex + 1) * GameClock.minutesPerDay
            for _ in 0..<6 {
                let result = w.advance(toMinute: target)
                if result == .pausedForIssue { answerIssues(&w) } else { break }
            }
            if w.airline.level > (levels.last?.level ?? 1) { levels.append((level: w.airline.level, day: day)) }
            if day == 364 { yearOne = (level: w.airline.level, reputation: w.airline.reputation, revenue: w.airline.stats.revenue) }
            if w.isBankrupt { break }
            let now = self.problems(w)
            if !now.isEmpty && problems.count < 10 { problems += now.map { "day \(day): \($0)" } }
        }
        return Playthrough(world: w, problems: problems, levels: levels, yearOne: yearOne)
    }

    func report(_ home: String, _ game: Playthrough, days: Int) {
        let w = game.world
        print("PLAYTEST \(home) after \(days) days: level \(w.airline.level), cash \(w.airline.cash), fleet \(w.aircraft.count), routes \(w.routes.count), flights \(w.airline.stats.flights), reputation \(Int(w.airline.reputation)), bankrupt \(w.isBankrupt), debt \(w.totalDebt)")
        if let year = game.yearOne {
            print("PLAYTEST \(home) after 365 days: level \(year.level), reputation \(Int(year.reputation)), revenue \(year.revenue)")
        }
        for step in game.levels { print("PLAYTEST \(home) level \(step.level) at day \(step.day)") }
        let campaigns = w.ops.campaigns.count
        let premium = w.routes.filter { $0.service == .premium }.count
        let hangar = w.hasHangar(at: w.airline.home)
        let slots = w.ops.slots.reduce(0) { $0 + $1.daily }
        print("PLAYTEST \(home) levers: jobs done \(w.ops.jobsDone.count), campaigns running \(campaigns), premium routes \(premium), hangar at home \(hangar), slots bought \(slots)")
    }

    @Test(arguments: ["SXM", "ASP", "YEV", "VLI"])
    func aCarefulPlayerGrowsWithoutBreakingTheWorld(home: String) throws {
        let days = 2 * 365
        let game = try play(home: home, days: days, seed: 11)
        let w = game.world
        report(home, game, days: days)
        for p in game.problems { print("PLAYTEST \(home) problem: \(p)") }
        #expect(game.problems.isEmpty, "\(home): \(game.problems.first ?? "")")
        #expect(w.airline.stats.flights > 0, "\(home): nothing flew")
        // Loose pacing (tools/sim/reputation_proto.py): from a good start a careful airline reaches level 3 in a year or a year and a
        // half (the model gives day 330 to 530 for this bot), not in the first few months (the $10M revenue alone takes most of a year).
        if home == "ASP" || home == "YEV" {
            let level3 = game.levels.first { $0.level >= 3 }?.day
            #expect(level3 != nil, "\(home): level 3 within two years (reputation \(Int(w.airline.reputation)), revenue \(w.airline.stats.revenue))")
            #expect((level3 ?? Int.max) >= 120, "\(home): level 3 at day \(level3 ?? -1) is too quick")
        }
    }

    @Test func anIslandStartGetsPermitsForItsNeighbours() throws {
        let island = World.startingPermits(home: try Fixtures.airport("SXM"))
        #expect(island.first == "SX")
        #expect(island.contains("BL") && island.contains("KN"))
        #expect(World.startingPermits(home: try Fixtures.airport("YEV")) == ["CA"])
    }

    @Test func everyStartRegionHasAProfitableFirstRoute() throws {
        for region in StartRegions.all {
            for home in region.headquarters {
                let w = try newGame(home: home, seed: 3)
                let idea = w?.routeIdeas(limit: 1).first
                print("PLAYTEST first route \(region.id) \(home): \(idea.map { "\($0.stops.joined(separator: "-")) \($0.typeID) \(Int($0.profitPerDay))/day" } ?? "none")")
            }
            let anyGood = try region.headquarters.contains { home in
                (try newGame(home: home, seed: 3))?.routeIdeas(limit: 1).first.map { $0.profitPerDay > 0 } ?? false
            }
            #expect(anyGood, "\(region.id): no headquarters has a profitable first route")
        }
    }
}
