// CoreWorld/Simulation.swift: the clock. `advance` runs the world forward minute by minute (jumping from event to event), stopping for issues.

public enum AdvanceResult: Sendable, Hashable {
    /// The clock reached the target time.
    case reachedTarget
    /// An issue that stops the game is waiting; resolve it, then advance again.
    case pausedForIssue
    case gameOver
}

extension World {
    /// Runs the world forward to the target minute, or until something needs the player. Safe to call again at once after an issue is resolved.
    @discardableResult
    public mutating func advance(toMinute target: Int) -> AdvanceResult {
        upgradeOldSave()
        if isBankrupt { return .gameOver }
        while clock.minute < target {
            if isPausedByIssue { return .pausedForIssue }
            let midnight = (clock.dayIndex + 1) * GameClock.minutesPerDay
            var next = min(target, midnight)
            for plane in aircraft {
                if let t = plane.eventMinute, t < next { next = t }
            }
            if next > clock.minute { clock.minute = next }
            // Midnight first: an aircraft due at 00:00 sees the new day's crew hours, slots and weather. (The other way round, a
            // crew hold at 00:00 ran to 06:00 the day after, 30 hours, and a 00:00 leg was charged to the day before.)
            if clock.minute == midnight { runDailyUpdate() }
            processDueAircraft()
            if isBankrupt { return .gameOver }
        }
        return isPausedByIssue ? .pausedForIssue : .reachedTarget
    }

    @discardableResult
    public mutating func advance(byMinutes minutes: Int) -> AdvanceResult { advance(toMinute: clock.minute + max(0, minutes)) }

    mutating func processDueAircraft() {
        var i = 0
        while i < aircraft.count {
            if let t = aircraft[i].eventMinute, t <= clock.minute {
                switch aircraft[i].status {
                case .onOrder: deliver(i)
                case .maintenance: finishMaintenance(i)
                case .boarding: depart(i)
                case .flying: arrive(i)
                case .idle, .grounded: break
                }
                // Safety net: an event that did not move on would otherwise repeat forever.
                if let t2 = aircraft[i].eventMinute, t2 <= clock.minute { aircraft[i].status = .boarding(until: clock.minute + 1) }
            }
            i += 1
        }
    }

    mutating func deliver(_ i: Int) {
        aircraft[i].status = .idle
        autoCrew(aircraftIndex: i, free: false)
        addNews(.aircraftDelivered, subject: aircraft[i].registration, amount: aircraft[i].id)
        if pausePolicy == .all { raise(.delivery(aircraftID: aircraft[i].id), options: [IssueOption(choice: .acknowledge, costUSD: 0, days: 0)]) }
    }

    mutating func finishMaintenance(_ i: Int) {
        aircraft[i].condition = max(aircraft[i].condition, Tuning.conditionAfterCheck)
        aircraft[i].status = aircraft[i].routeID == nil && aircraft[i].jobID == nil ? .idle : .boarding(until: clock.minute + 1)
    }
}
