// CoreWorld/FareDemand.swift: how many people a fare wins or loses compared with the going fare. Used by World.capture, so the
// simulation and the forecast agree. Prototype: fare_demand in tools/sim/route_proto.py.
import CoreSim

public enum FareDemand {
    /// Demand factor for `ratio` = going fare / the route's fare multiplier. Exactly 1 at ratio 1.
    /// Dearer than the going fare (ratio below 1): people fall as ratio^1.5.
    /// Cheaper (ratio above 1): people rise slowly along Tuning.fareGainByRatio, at most 1.5.
    public static func factor(ratio: Double) -> Double {
        if ratio <= 1.0 { return Powers.oneAndAHalf(max(0, ratio)) }
        return min(1.5, Tuning.fareGainByRatio.value(at: ratio))
    }
}
