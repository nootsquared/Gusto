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

extension PickupPlanner {
    /// Arbitrary sellers and locations. Straight-line miles, 15 mph travel, five-minute handoffs.
    public static func build(
        items: [Listing], sellers: [Seller], mode: RouteMode = .fastest,
        origin: GeoPoint, start: Double
    ) -> PickupPlan {
        let groups = Dictionary(grouping: items) { item in
            "\(item.sellerID):\(item.windows?.first?.locationID ?? item.sellerID)"
        }
        var remaining = groups.keys.sorted()
        var point = origin
        var time = start
        var miles = 0.0
        var stops: [PickupStop] = []
        func sellerFor(_ key: String) -> Seller {
            let item = groups[key]![0]
            return sellers.first { $0.id == item.sellerID }
                ?? Seller(
                    id: item.sellerID, name: item.sellerID,
                    rating: 0, pickups: 0, responds: "", student: false, area: "",
                    latitude: origin.latitude, longitude: origin.longitude)
        }
        func distance(_ seller: Seller) -> Double {
            let rad = Double.pi / 180
            let x =
                (seller.longitude - point.longitude) * rad
                * cos((seller.latitude + point.latitude) * rad / 2)
            let y = (seller.latitude - point.latitude) * rad
            return sqrt(x * x + y * y) * 3958.8
        }
        while !remaining.isEmpty {
            remaining.sort { a, b in
                let da = distance(sellerFor(a))
                let db = distance(sellerFor(b))
                let wa = groups[a]!.flatMap { $0.windows ?? [] }
                let wb = groups[b]!.flatMap { $0.windows ?? [] }
                let scoreA: Double
                let scoreB: Double
                switch mode {
                case .shortest:
                    scoreA = da
                    scoreB = db
                case .fastest:
                    scoreA = max(da / 15 * 3_600_000, (wa.map(\.start).max() ?? time) - time)
                    scoreB = max(db / 15 * 3_600_000, (wb.map(\.start).max() ?? time) - time)
                case .bestTiming:
                    scoreA = wa.map(\.end).min() ?? .infinity
                    scoreB = wb.map(\.end).min() ?? .infinity
                }
                return scoreA == scoreB ? a < b : scoreA < scoreB
            }
            let key = remaining.removeFirst()
            let seller = sellerFor(key)
            let goods = groups[key]!.sorted { $0.id < $1.id }
            let leg = distance(seller)
            miles += leg
            let windows = goods.flatMap { $0.windows ?? [] }
            time = max(time + ceil(leg / 15 * 60) * 60_000, windows.map(\.start).max() ?? time)
            let parts = Calendar.current.dateComponents(
                [.hour, .minute], from: Date(timeIntervalSince1970: time / 1000))
            stops.append(
                PickupStop(
                    seller: seller, items: goods,
                    minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                    serverID: key, locationID: goods.first?.windows?.first?.locationID,
                    windowEnd: windows.map(\.end).min()))
            point = GeoPoint(latitude: seller.latitude, longitude: seller.longitude)
            time += 300_000
        }
        return PickupPlan(
            stops: stops, mode: mode, elapsed: Int(ceil((time - start) / 60_000)), distance: miles)
    }
}
