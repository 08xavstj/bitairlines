"""Prototype of reputation pacing: how long a growing airline takes to reach the reputation each certificate level needs.
Mirrors Reputation.swift, Service.swift (reputationGain), IssueActions.swift (breakdowns) and Marketing.swift (campaigns).

    python tools/sim/reputation_proto.py

Per route departure:
    gain      = PER_FLIGHT x (1 + seat load) x service x (0.6 + 0.4 x on-time share)
    late      = late share x PER_LATE
    missed    = missed share x PER_MISSED  (checks and repairs on routes with one aircraft)
    breakdown = 0.00015 x wear (about 2) x heavy-check wear (about 1.1) x PER_BREAKDOWN
The weekly drift is left out: it only pulls down towards 15 + 85 x punctuality x comfort, which is 64 at 80% on time and
88 at 90%, far above the 22 and 35 that levels 3 and 4 need.

The growth curve is the playthrough bot's (PlaythroughTests): about 22,500 departures in two years at Alice Springs, rising
from 2 to 60 a day. Before rules 11 the bot ended two years at reputation 18 to 20 (level 2); this model gives 15 to 19.
"""
import math

PER_FLIGHT = 0.001        # Tuning.reputationPerFlight (0.0004 before rules 11)
PER_LATE = 0.0025         # Tuning.reputationPerLateDeparture (0.001)
PER_MISSED = 0.01         # Tuning.reputationPerMissedDeparture (0.004)
PER_BREAKDOWN = 0.8       # Tuning.reputationPerBreakdown
LEVEL_REPUTATION = {2: 11, 3: 22, 4: 35, 5: 50}
START = 10.0
CASES = {
    'careless': dict(load=0.75, on_time=0.88, missed=0.012),
    'middle': dict(load=0.80, on_time=0.90, missed=0.008),
    'careful': dict(load=0.85, on_time=0.95, missed=0.005),
}


def net(scale, load, on_time, missed, wear=2.0, heavy=1.1):
    gain = PER_FLIGHT * scale * (1 + load) * (0.6 + 0.4 * on_time)
    return gain - (1 - on_time) * PER_LATE * scale - missed * PER_MISSED * scale - 0.00015 * wear * heavy * PER_BREAKDOWN


def departures(day, shape):
    """Cumulative departures by `day`; both shapes give 22,523 at day 730."""
    if shape == 'linear':
        return 2 * day + 29 * day * day / 730
    raw = lambda d: 60 * (d + 250 * math.exp(-d / 250) - 250)  # noqa: E731  the fleet grows early
    return raw(day) * 22523 / raw(730)


def day_reaching(reputation, per_departure, shape, campaigns_from=None):
    """First day reputation reaches the level. With `campaigns_from`, radio (+1 every 30 days) and national (+2 every 60)
    run from that day on, as the bot does once only reputation stands between it and the next level."""
    for day in range(1, 3000):
        extra = 0.0
        if campaigns_from is not None and day > campaigns_from:
            extra = (day - campaigns_from) * (1 / 30 + 2 / 60)
        if START + departures(day, shape) * per_departure + extra >= reputation:
            return day
    return None


def main():
    for label, scale in (('before rules 11', 0.4), ('rules 11', 1.0)):
        print(f'--- {label} ---')
        for name, case in CASES.items():
            n = net(scale, **case)
            line = f'{name:9s} net {n:.5f} a departure, {1 / n:5.0f} departures a point, two-year bot ends near {START + 22523 * n:4.1f}'
            for shape in ('linear', 'early'):
                line += f' | {shape}: level 3 day {day_reaching(22, n, shape)}, level 4 day {day_reaching(35, n, shape)}'
            print(line)
    n = net(1.0, **CASES['middle'])
    print('rules 11 levers in departures: on-time job 0.15 =', round(0.15 / n), ', radio +1 =', round(1 / n), ', national +2 =', round(2 / n))
    for revenue_day in (250, 300, 365):
        print(f'revenue for level 3 met at day {revenue_day}: with campaigns level 3 at day',
              day_reaching(22, n, 'linear', campaigns_from=revenue_day))
    one = 716 * (PER_FLIGHT * 1.75 * 0.98 - 0.02 * PER_LATE)
    print(f'one Caravan, 716 flights a year, no breakdowns: +{one:.2f} a year (level 2 needs +1)')


if __name__ == '__main__':
    main()
