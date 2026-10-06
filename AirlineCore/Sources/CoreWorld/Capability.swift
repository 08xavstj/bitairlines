// CoreWorld/Capability.swift: can this aircraft use this airport today? One place that weighs the aircraft type, its kits (floats, skis,
// gravel kit, STOL kit), the airline's base upgrades (longer runway, paving, lights, fuel), the season (frozen lakes, daylight) and the game mode.
import CoreCatalog
import CoreSim

/// What an aircraft can land on once its kits are counted.
public struct Capability: Sendable, Hashable {
    public var paved: Bool
    public var gravel: Bool
    public var water: Bool
    /// Can land on a frozen lake in winter (wheel-skis).
    public var ice: Bool
    public var runwayFt: Int

    public init(type: AircraftType, kits: [Kit] = []) {
        paved = type.paved
        gravel = type.gravel
        water = type.water
        ice = false
        runwayFt = type.runwayFt
        if kits.contains(.floats) { paved = false; gravel = false; water = true }
        if kits.contains(.amphibious) { water = true }
        if kits.contains(.wheelSkis) { ice = true }
        if kits.contains(.gravelKit) { gravel = true }
        if kits.contains(.stolKit) { runwayFt = runwayFt * 3 / 4 }
    }
}

extension World {
    func base(at code: String) -> Base? { ops.bases.first { $0.airport == code } }

    /// The runway the airline has at an airport (a base extension adds to it).
    public func runwayFt(at airport: Airport) -> Int {
        airport.runwayFt + (base(at: airport.code)?.has(.runwayExtension) == true ? Tuning.runwayExtensionFt : 0)
    }

    /// The surface the airline lands on (a paved base turns gravel into tarmac).
    public func surface(at airport: Airport) -> RunwaySurface {
        airport.surface == .gravel && base(at: airport.code)?.has(.paving) == true ? .paved : airport.surface
    }

    /// Runway lights: paved and scheduled airports have them, small strips only when the airline puts them in.
    public func isLit(_ airport: Airport) -> Bool {
        airport.surface == .paved || airport.scheduled || airport.kind == .large || airport.kind == .medium || base(at: airport.code)?.has(.lights) == true
    }

    /// Whether fuel is sold here. Only matters in Realism, where small strips have none unless the airline builds a depot.
    public func sellsFuel(_ airport: Airport) -> Bool {
        airport.kind == .large || airport.kind == .medium || airport.scheduled || base(at: airport.code)?.has(.fuelDepot) == true
    }

    /// A lake (a water aerodrome) iced over: from November to April north of 60 degrees, December to March from 50 to 60 degrees,
    /// and the same months shifted by half a year in the far south.
    public func isFrozen(_ airport: Airport, month: Int) -> Bool {
        guard ops.mode.lakesFreeze, airport.surface == .water else { return false }
        let lat = airport.latitude
        let m = lat >= 0 ? month : ((month + 5) % 12) + 1
        let a = lat < 0 ? -lat : lat
        if a >= 60 { return m >= 11 || m <= 4 }
        if a >= 50 { return m == 12 || m <= 3 }
        return false
    }

    /// Whether an aircraft with this capability can use the airport. With `month`, a frozen lake counts as ice; without it, the
    /// question is "ever, in some season".
    public func canUse(_ cap: Capability, at airport: Airport, month: Int? = nil) -> Bool {
        let surf = surface(at: airport)
        if surf == .water {
            if let month, isFrozen(airport, month: month) { return cap.ice }
            return cap.water || (month == nil && cap.ice && ops.mode.lakesFreeze)
        }
        if !ops.mode.checksRunways { return cap.paved || cap.gravel }
        let fits = runwayFt(at: airport) >= cap.runwayFt
        return surf == .paved ? (cap.paved || cap.gravel) && fits : cap.gravel && fits
    }

    public func canUse(type: AircraftType, kits: [Kit] = [], at airport: Airport, month: Int? = nil) -> Bool {
        canUse(Capability(type: type, kits: kits), at: airport, month: month)
    }

    // MARK: Daylight

    /// Hours of usable light at a latitude on a day of the year: sunrise to sunset plus civil twilight, never less than three hours.
    public static func daylightHours(latitude: Double, dayOfYear: Int) -> Double {
        let rad = 3.141592653589793 / 180.0
        let declination = -23.44 * rad * GeoMath.cosine(2.0 * 3.141592653589793 * Double(dayOfYear + 10) / 365.0)
        let phi = latitude * rad
        let tanProduct = (GeoMath.sine(phi) / GeoMath.cosine(phi)) * (GeoMath.sine(declination) / GeoMath.cosine(declination))
        let x = -tanProduct
        let hourAngle: Double
        if x <= -1 { hourAngle = 3.141592653589793 } else if x >= 1 { hourAngle = 0 } else { hourAngle = 1.5707963267948966 - GeoMath.arcSine(x) }
        let sunHours = 24.0 * hourAngle / 3.141592653589793
        return min(24, max(3, sunHours + 1.0))
    }

    /// The minutes of the day (local) when an unlit strip may be used: centred on noon.
    func daylightWindow(_ airport: Airport, day: Int) -> (open: Int, close: Int) {
        let dayOfYear = day - World.dayOfYearStart(of: day)
        let hours = World.daylightHours(latitude: airport.latitude, dayOfYear: dayOfYear)
        let half = Int(hours * 30.0)
        return (max(0, 720 - half), min(1440, 720 + half))
    }

    static func dayOfYearStart(of day: Int) -> Int {
        let date = CalendarDate(dayIndex: day)
        var start = 0
        for y in CalendarDate.epochYear..<date.year { start += CalendarDate.isLeap(y) ? 366 : 365 }
        return start
    }

    /// If a flight from `a` to `b` taking `blockMinutes` may not leave now because one end is an unlit strip in the dark,
    /// the minute it may leave; nil if it may go now.
    func darkHold(from a: Airport, to b: Airport, blockMinutes: Int) -> Int? {
        guard ops.mode.daylightLimits else { return nil }
        let day = clock.dayIndex
        let now = clock.minuteOfDay
        var earliest = 0
        var latestDeparture = 1440
        if !isLit(a) {
            let w = daylightWindow(a, day: day)
            earliest = max(earliest, w.open)
            latestDeparture = min(latestDeparture, w.close)
        }
        if !isLit(b) {
            let w = daylightWindow(b, day: day)
            earliest = max(earliest, w.open - blockMinutes)
            latestDeparture = min(latestDeparture, w.close - blockMinutes)
        }
        // In deep winter a long leg may not fit in the light at all; then it leaves at first light and lands in the twilight.
        if earliest > latestDeparture { latestDeparture = earliest + 60 }
        if now >= earliest && now <= latestDeparture { return nil }
        if now < earliest { return day * GameClock.minutesPerDay + earliest }
        // Too late today: first light tomorrow.
        let tomorrowA = isLit(a) ? 0 : daylightWindow(a, day: day + 1).open
        let tomorrowB = isLit(b) ? 0 : daylightWindow(b, day: day + 1).open - blockMinutes
        return (day + 1) * GameClock.minutesPerDay + max(0, tomorrowA, tomorrowB)
    }
}
