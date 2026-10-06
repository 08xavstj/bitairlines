// CoreWorld/AwayCatchUp.swift: moving the game on while the player is away from it.

extension World {
    /// Moves the game on for a break away from the game. A breakdown waits in the inbox (the aircraft stays grounded) so one broken
    /// aircraft does not stop the rest of the fleet; it stops the game again once the break is over. Running out of money still
    /// stops at once, so the airline cannot go bankrupt while the player is not looking.
    @discardableResult
    public mutating func advanceAway(byMinutes minutes: Int) -> AdvanceResult {
        let target = clock.minute + max(0, minutes)
        var held: [Int] = []
        var result = advance(toMinute: target)
        while result == .pausedForIssue {
            let stopping = issues.indices.filter { issues[$0].pausesGame }
            guard !stopping.isEmpty, stopping.allSatisfy({ World.isBreakdown(issues[$0].kind) }) else { break }
            for i in stopping {
                issues[i].pausesGame = false
                held.append(issues[i].id)
            }
            result = advance(toMinute: target)
        }
        for i in issues.indices where held.contains(issues[i].id) { issues[i].pausesGame = pauses(issues[i]) }
        return result
    }

    static func isBreakdown(_ kind: IssueKind) -> Bool {
        if case .breakdown = kind { return true }
        return false
    }
}
