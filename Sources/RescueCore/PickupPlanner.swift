import Foundation

/// Local deterministic plan estimates. No directions API, GPS or backend is used.
public enum PickupPlanner {
    public static func build(items: [Listing], mode: RouteMode = .fastest) -> PickupPlan {
        let groups = Dictionary(grouping: items, by: \.sellerID)
        var order = ["maya", "alex", "nina", "jordan", "sam"]
        if mode == .shortest { order = ["maya", "sam", "alex", "nina", "jordan"] }
        if mode == .bestTiming {
            order.sort { a, b in
                let urgentA = groups[a]?.contains { $0.freshness == .useSoon } ?? false
                let urgentB = groups[b]?.contains { $0.freshness == .useSoon } ?? false
                if urgentA != urgentB { return urgentA }
                return ["maya", "alex", "nina", "jordan", "sam"].firstIndex(of: a)! < [
                    "maya", "alex", "nina", "jordan", "sam",
                ].firstIndex(of: b)!
            }
        }
        var minute = 16 * 60 + 15
        var stops: [PickupStop] = []
        for id in order {
            guard let goods = groups[id],
                let seller = MockCatalog.sellers.first(where: { $0.id == id })
            else { continue }
            if !stops.isEmpty { minute += [9, 12, 12, 10][min(stops.count - 1, 3)] }
            stops.append(PickupStop(seller: seller, items: goods, minute: minute))
        }
        let count = stops.count
        return PickupPlan(
            stops: stops, mode: mode,
            elapsed: count == 0
                ? 0 : count * 9 + 1 + (mode == .shortest ? 3 : mode == .bestTiming ? 6 : 0),
            distance: count == 0
                ? 0 : max(0.2, Double(count) * 0.52 - (mode == .shortest ? 0.3 : 0)))
    }

    /// Delay the requested stop and every later stop; never move paid stops.
    public static func shift(_ plan: inout PickupPlan, sellerID: String, by minutes: Int) {
        guard minutes > 0, let index = plan.stops.firstIndex(where: { $0.id == sellerID }) else {
            return
        }
        for i in index..<plan.stops.count
        where plan.stops[i].status != .paid && plan.stops[i].status != .skipped {
            plan.stops[i].minute += minutes
        }
        plan.elapsed += minutes
    }
}
