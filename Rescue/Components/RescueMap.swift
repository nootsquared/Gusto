import MapKit
import SwiftUI

/// MapKit for live tiles; exact native reconstruction of source MapArt for offline demos.
struct RescueMap: View {
    @Environment(AppStore.self) private var store
    @AppStorage("useLiveMap") private var liveMap = false
    let items: [Listing]
    var stops: [PickupStop] = []
    @Binding var selectedID: String?
    @State private var position: MapCameraPosition = .region(Self.region)
    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.278, longitude: -83.740),
        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.022))
    private var userPoint: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 42.277, longitude: -83.741)
    }
    // Keep the Make listing positions; projecting them also works with the optional live map.
    private static let listingPositions: [String: CGPoint] = [
        "straw": CGPoint(x: 38, y: 40),
        "yog": CGPoint(x: 62, y: 30),
        "bread": CGPoint(x: 72, y: 58),
        "pasta": CGPoint(x: 50, y: 72),
        "avo": CGPoint(x: 26, y: 62),
        "eggs": CGPoint(x: 66, y: 44),
        "bana": CGPoint(x: 42, y: 50),
        "gran": CGPoint(x: 80, y: 24),
        "spin": CGPoint(x: 20, y: 36),
        "milk": CGPoint(x: 56, y: 84),
        "prep": CGPoint(x: 76, y: 70),
        "cereal": CGPoint(x: 34, y: 80),
        "chips": CGPoint(x: 44, y: 34),
        "trail": CGPoint(x: 58, y: 38),
        "hummus": CGPoint(x: 24, y: 48),
        "bars": CGPoint(x: 48, y: 64),
        "curry": CGPoint(x: 36, y: 46),
        "bowl": CGPoint(x: 64, y: 50),
        "soup": CGPoint(x: 30, y: 56),
        "salad": CGPoint(x: 54, y: 78),
    ]
    private func coordinate(_ item: Listing) -> CLLocationCoordinate2D {
        if store.isBackend {
            let seller = store.seller(item.sellerID)
            return CLLocationCoordinate2D(latitude: seller.latitude, longitude: seller.longitude)
        }
        let point = Self.listingPositions[item.image] ?? CGPoint(x: 50, y: 50)
        return CLLocationCoordinate2D(
            latitude: Self.region.center.latitude + (0.5 - point.y / 100)
                * Self.region.span.latitudeDelta,
            longitude: Self.region.center.longitude + (point.x / 100 - 0.5)
                * Self.region.span.longitudeDelta)
    }
    var body: some View {
        Group {
            if liveMap {
                Map(position: $position) {
                    Annotation("Demo starting point", coordinate: userPoint) { userDot }
                    if stops.isEmpty {
                        ForEach(Array(items.prefix(100))) { item in
                            Annotation(item.name, coordinate: coordinate(item), anchor: .bottom) {
                                pricePin(item)
                            }
                            if selectedID == item.id {
                                MapCircle(center: coordinate(item), radius: 120).foregroundStyle(
                                    Theme.sage.opacity(0.15)
                                ).stroke(Theme.sage.opacity(0.35), lineWidth: 1)
                            }
                        }
                    } else {
                        MapPolyline(
                            coordinates: [userPoint]
                                + stops.map {
                                    CLLocationCoordinate2D(
                                        latitude: $0.seller.latitude, longitude: $0.seller.longitude
                                    )
                                }
                        ).stroke(Theme.deep, lineWidth: 5)
                        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                            Annotation(
                                stop.seller.firstName,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: stop.seller.latitude, longitude: stop.seller.longitude
                                )
                            ) { stopPin(stop, index: index) }
                        }
                    }
                }.mapStyle(
                    .standard(
                        elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
                )
                .mapControlVisibility(.hidden)
            } else {
                GeometryReader { geometry in
                    ZStack {
                        DemoMapBackdrop()
                        if !stops.isEmpty {
                            Path { path in
                                path.move(to: projected(userPoint, size: geometry.size))
                                for stop in stops {
                                    path.addLine(
                                        to: projected(
                                            CLLocationCoordinate2D(
                                                latitude: stop.seller.latitude,
                                                longitude: stop.seller.longitude),
                                            size: geometry.size))
                                }
                            }.stroke(
                                Theme.deep,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                                stopPin(stop, index: index).position(
                                    projected(
                                        CLLocationCoordinate2D(
                                            latitude: stop.seller.latitude,
                                            longitude: stop.seller.longitude), size: geometry.size))
                            }
                        } else {
                            ForEach(Array(items.prefix(100))) { item in
                                let point = projected(coordinate(item), size: geometry.size)
                                if selectedID == item.id {
                                    Circle().fill(Theme.sage.opacity(0.15)).overlay(
                                        Circle().stroke(Theme.sage.opacity(0.3))
                                    ).frame(width: 100, height: 100).position(point)
                                }
                                pricePin(item).position(point).zIndex(selectedID == item.id ? 2 : 1)
                            }
                        }
                        userDot.position(projected(userPoint, size: geometry.size))
                    }
                }
            }
        }.clipped().accessibilityElement(children: .contain)
    }
    private func projected(_ coordinate: CLLocationCoordinate2D, size: CGSize) -> CGPoint {
        let region = Self.region
        let x = 0.5 + (coordinate.longitude - region.center.longitude) / region.span.longitudeDelta
        let y = 0.5 - (coordinate.latitude - region.center.latitude) / region.span.latitudeDelta
        return CGPoint(x: x * size.width, y: y * size.height)
    }
    private var userDot: some View {
        Circle().fill(Color(red: 0.23, green: 0.51, blue: 0.77)).frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 3).accessibilityLabel(
                "Fixed demo starting point")
    }
    private func pricePin(_ item: Listing) -> some View {
        let selected = selectedID == item.id
        return Button {
            withAnimation(Theme.spring) { selectedID = item.id }
            Haptic.tap()
        } label: {
            HStack(spacing: 5) {
                if selected {
                    FoodPhoto(name: item.image).frame(width: 30, height: 30).clipShape(Circle())
                }
                Text(Money.text(item.price)).rescueFont(13, .semibold).monospacedDigit()
            }.padding(selected ? 4 : 8).padding(.trailing, selected ? 6 : 0).foregroundStyle(
                selected ? Theme.paper : Theme.ink
            )
            .background(selected ? Theme.ink : Theme.paper, in: Capsule()).shadow(
                color: Theme.ink.opacity(0.16), radius: 6, y: 4
            ).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("\(item.name), \(Money.text(item.price))")
    }
    private func stopPin(_ stop: PickupStop, index: Int) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(stop.status == .paid ? Theme.sage : Theme.ink).frame(
                    width: 36, height: 36
                ).overlay(Circle().stroke(Theme.paper, lineWidth: 3)).shadow(radius: 4)
                if stop.status == .paid {
                    Image(systemName: "checkmark").foregroundStyle(Theme.paper)
                } else {
                    Text("\(index + 1)").rescueFont(15, .bold).foregroundStyle(Theme.paper)
                }
            }
            if stop.status == .confirmed || stop.status == .waiting {
                Text("\(stop.seller.firstName) \(stop.status == .confirmed ? "✓" : "· awaiting")")
                    .rescueFont(10, .semibold).padding(5).foregroundStyle(Theme.paper).background(
                        stop.status == .waiting ? Theme.apricot : Theme.sage, in: Capsule())
            }
        }.accessibilityLabel("Stop \(index + 1), \(stop.seller.name), \(stop.status.rawValue)")
    }
}

private struct DemoMapBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                func point(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: x / 100 * size.width, y: y / 100 * size.height)
                }
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(red: 0.937, green: 0.91, blue: 0.863)))
                var river = Path()
                river.move(to: point(-5, 78))
                river.addCurve(to: point(45, 88), control1: point(15, 70), control2: point(25, 92))
                river.addCurve(to: point(105, 86), control1: point(65, 84), control2: point(75, 96))
                river.addLine(to: point(105, 105))
                river.addLine(to: point(-5, 105))
                river.closeSubpath()
                context.fill(river, with: .color(Color(red: 0.812, green: 0.867, blue: 0.878)))
                for rect in [
                    CGRect(x: 8, y: 12, width: 22, height: 16),
                    CGRect(x: 58, y: 48, width: 18, height: 12),
                    CGRect(x: 84, y: 6, width: 14, height: 14),
                ] {
                    context.fill(
                        Path(
                            roundedRect: CGRect(
                                x: rect.minX / 100 * size.width, y: rect.minY / 100 * size.height,
                                width: rect.width / 100 * size.width,
                                height: rect.height / 100 * size.height), cornerRadius: 8),
                        with: .color(Color(red: 0.859, green: 0.894, blue: 0.824)))
                }
                for x in [10.0, 24, 38, 52, 66, 80, 94] {
                    var p = Path()
                    p.move(to: point(x, -5))
                    p.addLine(to: point(x + 4, 105))
                    context.stroke(p, with: .color(Theme.ivory), lineWidth: 5)
                }
                for y in [8.0, 20, 33, 46, 59, 71] {
                    var p = Path()
                    p.move(to: point(-5, y))
                    p.addLine(to: point(105, y - 3))
                    context.stroke(p, with: .color(Theme.ivory), lineWidth: 5)
                }
                var avenue = Path()
                avenue.move(to: point(-5, 54))
                avenue.addCurve(
                    to: point(105, 40), control1: point(25, 50), control2: point(45, 64))
                context.stroke(
                    avenue, with: .color(Color(red: 0.965, green: 0.89, blue: 0.749)), lineWidth: 9)
            }
            Text("LINDEN PARK").font(.system(size: 10, weight: .medium)).foregroundStyle(
                Theme.sage.opacity(0.7)
            ).position(x: geo.size.width * 0.22, y: geo.size.height * 0.19)
            Text("NORTH CAMPUS").font(.system(size: 10, weight: .medium)).foregroundStyle(
                Theme.muted
            ).position(x: geo.size.width * 0.76, y: geo.size.height * 0.12)
            Text("HARBOR").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
                .position(x: geo.size.width * 0.7, y: geo.size.height * 0.92)
        }
    }
}
