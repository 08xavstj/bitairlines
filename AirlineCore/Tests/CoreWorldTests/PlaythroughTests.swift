import Testing
import CoreCatalog
@testable import CoreWorld

/// A simple bot plays whole games the way a careful player would: it opens the best suggested routes, buys aircraft for them,
/// takes jobs with idle aircraft, answers every issue, takes perks and the next certificate. After every game day it checks
/// that the world still holds together. The PLAYTEST lines in the log show how far each start got.
@Suite struct PlaythroughTests {
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
        // Idle aircraft: give each a route of its own type.
        for plane in w.aircraft where plane.isDelivered && plane.allRouteIDs.isEmpty && plane.jobID == nil {
            guard let idea = ideas.first(where: { $0.typeID == plane.typeID && $0.profitPerDay > 0 }) else { continue }
            let existing = w.routes.first { Set($0.stops) == Set(idea.stops) }?.id
            let routeID = existing ?? (try? w.createRoute(stops: idea.stops))
            if let routeID { try? w.assign(aircraftID: plane.id, toRoute: routeID) }
        }
        // With money to spare, buy a used aircraft for the best idea that needs one.
        if w.aircraft.count < 14, let idea = ideas.first(where: { $0.profitPerDay > 500 }),
           let listing = w.market.listings.filter({ $0.typeID == idea.typeID }).min(by: { $0.price < $1.price }),
           w.airline.cash > listing.price + 400_000 {
            _ = try? w.buyUsed(listingID: listing.id)
        }
        // Idle aircraft fly jobs they can take.
        for job in w.ops.jobs where !job.isTaken {
            if let plane = w.aircraft.first(where: { $0.allRouteIDs.isEmpty && $0.jobID == nil && w.jobProblem(jobID: job.id, aircraftID: $0.id) == nil }) {
                try? w.takeJob(jobID: job.id, aircraftID: plane.id)
            }
        }
        if w.airline.level >= 2 && !w.hasStaff(.fleetPlanner) && w.airline.cash > 2_000_000 { try? w.hire(.fleetPlanner) }
    }

    /// Answers every issue that stops the game with the cheapest choice the airline can pay for.
    func answerIssues(_ w: inout World) {
        for _ in 0..<20 where w.isPausedByIssue {
            guard let issue = w.issues.first(where: { $0.pausesGame }) else { return }
            let affordable = issue.options.filter { $0.costUSD <= max(0, w.airline.cash) }
            let pick = affordable.min { ($0.costUSD, $0.days) < ($1.costUSD, $1.days) } ?? issue.options.last
            guard let choice = pick?.choice else { return }
            if (try? w.resolve(issueID: issue.id, choice: choice)) == nil {
                // Nothing it offers can be taken: drop the notice so the bot carries on, and say so.
                print("PLAYTEST could not answer issue \(issue.kind) at day \(w.clock.dayIndex)")
                return
            }
        }
    }

    func play(home: String, days: Int, seed: UInt64) throws -> (world: World, problems: [String]) {
        guard var w = try newGame(home: home, seed: seed) else { return (try Fixtures.world(), ["no starter aircraft can use \(home)"]) }
        var problems: [String] = []
        for day in 0..<days {
            if day % 7 == 0 { decide(&w) }
            let target = (w.clock.dayIndex + 1) * GameClock.minutesPerDay
            for _ in 0..<6 {
                let result = w.advance(toMinute: target)
                if result == .pausedForIssue { answerIssues(&w) } else { break }
            }
            if w.isBankrupt { break }
            let now = self.problems(w)
            if !now.isEmpty && problems.count < 10 { problems += now.map { "day \(day): \($0)" } }
        }
        return (w, problems)
    }

    func report(_ home: String, _ w: World, days: Int) {
        print("PLAYTEST \(home) after \(days) days: level \(w.airline.level), cash \(w.airline.cash), fleet \(w.aircraft.count), routes \(w.routes.count), flights \(w.airline.stats.flights), reputation \(Int(w.airline.reputation)), bankrupt \(w.isBankrupt), debt \(w.totalDebt)")
    }

    @Test(arguments: ["SXM", "ASP", "YEV", "VLI"])
    func aCarefulPlayerGrowsWithoutBreakingTheWorld(home: String) throws {
        let days = 2 * 365
        let (w, problems) = try play(home: home, days: days, seed: 11)
        report(home, w, days: days)
        for p in problems { print("PLAYTEST \(home) problem: \(p)") }
        #expect(problems.isEmpty, "\(home): \(problems.first ?? "")")
        #expect(w.airline.stats.flights > 0, "\(home): nothing flew")
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
