// CoreWorld/FleetActions.swift: what the player can do about money and aircraft: buy, sell, permits, loans, certificate upgrades, paint.
import CoreCatalog
import CoreSim

extension World {
    // MARK: Aircraft

    /// Buys a used aircraft from the market. It arrives at the home airport after the listing's delivery time. Returns the aircraft id.
    @discardableResult
    public mutating func buyUsed(listingID: Int) throws -> Int {
        guard let listing = market.listings.first(where: { $0.id == listingID }) else { throw WorldError.unknownListing(listingID) }
        guard let type = AircraftCatalog.type(listing.typeID) else { throw WorldError.unknownType(listing.typeID) }
        guard type.level <= airline.level else { throw WorldError.levelTooLow(required: type.level) }
        guard airline.cash >= listing.price else { throw WorldError.notEnoughCash(needed: listing.price) }
        airline.cash -= listing.price
        let id = takeAircraftID()
        let delivery = clock.minute + listing.deliveryDays * GameClock.minutesPerDay
        aircraft.append(Aircraft(id: id, typeID: type.id, registration: nextRegistration(), builtDay: clock.dayIndex - Int(listing.ageYears * 365.25),
                                 condition: listing.condition, price: listing.price, location: airline.home, status: .onOrder(until: delivery)))
        market.listings.removeAll { $0.id == listingID }
        return id
    }

    /// Orders a new aircraft (types in production only). Delivery takes longer for bigger types.
    @discardableResult
    public mutating func orderNew(typeID: String) throws -> Int {
        guard let type = AircraftCatalog.type(typeID) else { throw WorldError.unknownType(typeID) }
        guard type.inProduction else { throw WorldError.notInProduction }
        guard type.level <= airline.level else { throw WorldError.levelTooLow(required: type.level) }
        guard airline.cash >= type.priceUSD else { throw WorldError.notEnoughCash(needed: type.priceUSD) }
        airline.cash -= type.priceUSD
        let id = takeAircraftID()
        let delivery = clock.minute + Valuation.newDeliveryDays(level: type.level) * GameClock.minutesPerDay
        aircraft.append(Aircraft(id: id, typeID: type.id, registration: nextRegistration(), builtDay: clock.dayIndex, condition: 100,
                                 price: type.priceUSD, location: airline.home, status: .onOrder(until: delivery)))
        return id
    }

    /// What a dealer pays for the aircraft today.
    public func saleValue(of plane: Aircraft) -> Int {
        guard let type = plane.type else { return 0 }
        return Int(Double(Valuation.value(type: type, ageYears: plane.ageYears(atDay: clock.dayIndex), condition: plane.condition)) * 0.85)
    }

    /// Sells an aircraft that has no route. Returns the price.
    @discardableResult
    public mutating func sell(aircraftID: Int) throws -> Int {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        let plane = aircraft[i]
        guard plane.isDelivered else { throw WorldError.notDelivered }
        guard plane.routeID == nil else { throw WorldError.aircraftHasRoute }
        if case .flying = plane.status { throw WorldError.aircraftBusy }
        let price = saleValue(of: plane)
        airline.cash += price
        aircraft.remove(at: i)
        addNews(.aircraftSold, subject: plane.registration, amount: price)
        return price
    }

    public mutating func setLivery(aircraftID: Int, livery: SpecialLivery?) throws {
        guard let i = aircraftIndex(aircraftID) else { throw WorldError.unknownAircraft(aircraftID) }
        aircraft[i].livery = livery
    }

    /// Repaints the whole fleet: every aircraft without a special livery follows the airline's branding.
    public mutating func setBranding(_ branding: Branding) { airline.branding = branding }

    // MARK: Permits and certificate

    public mutating func buyPermit(country: String) throws {
        guard CountryCatalog.country(country) != nil else { throw WorldError.unknownAirport(country) }
        guard !airline.permits.contains(country) else { throw WorldError.alreadyHasPermit }
        let price = Progression.permitPrice(country: country)
        guard airline.cash >= price else { throw WorldError.notEnoughCash(needed: price) }
        airline.cash -= price
        airline.permits.append(country)
        addNews(.permit, subject: country, amount: price)
    }

    public var nextLevelRequirement: LevelRequirement? { Progression.requirement(forNextLevelAfter: airline.level) }

    public var canUpgradeCertificate: Bool {
        guard let r = nextLevelRequirement else { return false }
        return Progression.meets(r, airline: airline) && airline.cash >= r.fee
    }

    public mutating func upgradeCertificate() throws {
        guard let r = nextLevelRequirement else { throw WorldError.requirementsNotMet }
        guard Progression.meets(r, airline: airline) else { throw WorldError.requirementsNotMet }
        guard airline.cash >= r.fee else { throw WorldError.notEnoughCash(needed: r.fee) }
        airline.cash -= r.fee
        airline.level = r.level
        issues.removeAll { if case .certificateReady = $0.kind { return true } else { return false } }
        addNews(.certificate, subject: "level", amount: r.level)
        addListings(4)
    }

    // MARK: Loans

    /// The most the airline may owe in total: a starter allowance plus a share of lifetime revenue.
    public var borrowingLimit: Int { 1_500_000 + airline.stats.revenue / 4 }

    public var totalDebt: Int { airline.loans.reduce(0) { $0 + $1.remaining } }

    public mutating func takeLoan(amount: Int, annualRate: Double = 0.085, months: Int = 60) throws {
        guard amount >= 10_000 else { throw WorldError.invalidAmount }
        guard totalDebt + amount <= borrowingLimit else { throw WorldError.notEnoughCash(needed: totalDebt + amount - borrowingLimit) }
        airline.loans.append(Loan(id: takeLoanID(), remaining: amount, annualRate: annualRate, monthlyPrincipal: max(1, amount / months), monthsLeft: months))
        airline.cash += amount
        addNews(.loan, subject: "taken", amount: amount)
    }

    public mutating func repayLoan(id: Int) throws {
        guard let i = airline.loans.firstIndex(where: { $0.id == id }) else { throw WorldError.invalidChoice }
        let owed = airline.loans[i].remaining
        guard airline.cash >= owed else { throw WorldError.notEnoughCash(needed: owed) }
        airline.cash -= owed
        airline.loans.remove(at: i)
        addNews(.loan, subject: "repaid", amount: owed)
    }
}
