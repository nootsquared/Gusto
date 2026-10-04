import MapKit
import SwiftUI

struct PickupRouteMap: View {
    @Environment(LocationController.self) private var location
    let stops: [PickupStop]
    @State private var routes: [MKPolyline] = []
    @State private var travelMinutes: Int?
    private func point(_ stop: PickupStop) -> CLLocationCoordinate2D {
        if let exact = stop.privateLocation, exact.cacheUntil > Date().timeIntervalSince1970 * 1000 {
            return CLLocationCoordinate2D(latitude: exact.latitude, longitude: exact.longitude)
        }
        return CLLocationCoordinate2D(latitude: stop.seller.latitude, longitude: stop.seller.longitude)
    }
    private var routeKey: String {
        "\(location.selection?.latitude ?? 0):\(location.selection?.longitude ?? 0):"
            + stops.map { "\($0.id):\(point($0).latitude):\(point($0).longitude)" }.joined(separator: "|")
    }
    var body: some View {
        Map {
            if location.usingGPS { UserAnnotation() }
            if let origin = location.selection {
                Marker("Starting point", systemImage: "location.fill", coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)).tint(Theme.sage)
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Marker("\(index + 1). \(stop.seller.firstName)", coordinate: point(stop)).tint(Theme.save)
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                MapPolyline(route).stroke(Theme.save, lineWidth: 4)
            }
        }.mapStyle(.standard(elevation: .flat)).mapControls { MapCompass() }
            .overlay(alignment: .topLeading) {
                if let travelMinutes {
                    Text("\(travelMinutes) min travel").rescueFont(12, .semibold)
                        .padding(10).background(Theme.paper, in: Capsule()).padding(12)
                }
            }.overlay(alignment: .bottomTrailing) {
                if let first = stops.first {
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: point(first)))
                        item.name = "Pickup with \(first.seller.firstName)"
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label("Directions", systemImage: "arrow.up.right").rescueFont(12, .semibold)
                            .padding(10).background(Theme.paper, in: Capsule())
                    }.buttonStyle(.plain).padding(12)
                }
            }.accessibilityIdentifier("pickup-apple-map")
            .task(id: routeKey) {
                routes = []
                travelMinutes = nil
                guard let origin = location.selection else { return }
                var start = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
                var paths: [MKPolyline] = []
                var seconds = 0.0
                for stop in stops {
                    let destination = point(stop)
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
                    request.transportType = .automobile
                    guard let response = try? await MKDirections(request: request).calculate(),
                        let route = response.routes.first, !Task.isCancelled else { return }
                    paths.append(route.polyline)
                    seconds += route.expectedTravelTime
                    start = destination
                }
                guard !Task.isCancelled else { return }
                routes = paths
                travelMinutes = Int(ceil(seconds / 60))
            }
    }
}

struct SavingsHero: View {
    let totals: Totals
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You save").rescueFont(13, .medium).foregroundStyle(Theme.paper.opacity(0.7))
            Text(Money.text(totals.saved)).rescueFont(46, .bold).monospacedDigit().tracking(-1)
            Divider().overlay(Theme.paper.opacity(0.15)).padding(.vertical, 6)
            HStack(alignment: .top) {
                metric("Retail value", Money.text(totals.retail), strike: true)
                Spacer()
                metric("You pay", Money.text(totals.pay))
                Spacer()
                metric("Food saved", String(format: "%.1f lb", totals.pounds))
            }
        }.padding(20).foregroundStyle(Theme.paper).background(
            Theme.deep, in: RoundedRectangle(cornerRadius: 24))
    }
    private func metric(_ label: String, _ value: String, strike: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).rescueFont(12).foregroundStyle(Theme.paper.opacity(0.6))
            Text(value).rescueFont(14, .semibold).strikethrough(strike).monospacedDigit()
        }
    }
}

struct CartView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(LocationController.self) private var location
    private var groups: [PickupStop] { PickupPlanner.build(items: store.cartItems).stops }
    var body: some View {
        Group {
            if store.cart.isEmpty {
                VStack {
                    EmptyState(
                        title: "Your cart is empty", message: "Good food is waiting nearby.",
                        symbol: "bag")
                    Button {
                        Haptic.tap()
                        router.tab = .discover
                        router.sheet = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .font(.system(size: 22, weight: .medium))
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.10), in: Circle())
                            Text("Discover food").rescueFont(17, .semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Theme.butter)
                        }.foregroundStyle(Theme.paper).padding(.horizontal, 18)
                            .frame(height: 66)
                            .background(
                                LinearGradient(
                                    colors: [Theme.deep, Theme.sage],
                                    startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 22)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Theme.deep.opacity(0.16), radius: 12, y: 6)
                    }.buttonStyle(.plain).accessibilityIdentifier("discover-food")
                        .padding(20)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("\(store.cart.count) items · \(groups.count) sellers · one trip")
                            .rescueFont(14).foregroundStyle(Theme.secondary)
                        SavingsHero(totals: store.cartTotals)
                        ForEach(groups) { stop in
                            VStack(alignment: .leading, spacing: 10) {
                                SellerRow(seller: stop.seller)
                                Text("\(stop.seller.area) area · \(stop.items.first?.pickup ?? "")")
                                    .rescueFont(13).foregroundStyle(Theme.secondary)
                                ForEach(stop.items) { item in
                                    HStack(spacing: 12) {
                                        FoodPhoto(name: item.image).frame(width: 48, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).rescueFont(15, .medium)
                                            Text(Money.text(item.retail)).strikethrough()
                                                .rescueFont(13).foregroundStyle(Theme.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Text(Money.text(item.price)).rescueFont(17, .semibold)
                                            .monospacedDigit()
                                        Button {
                                            withAnimation(Theme.spring) { store.remove(item.id) }
                                        } label: {
                                            Image(systemName: "xmark").rescueFont(12).frame(
                                                width: 44, height: 44)
                                        }.buttonStyle(.plain).disabled(store.runActive)
                                            .accessibilityLabel("Remove \(item.name)")
                                            .accessibilityIdentifier("remove-\(item.id)")
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    }.padding(20)
                }.safeAreaInset(edge: .bottom) {
                    BottomAction {
                        PrimaryButton(
                            title: store.runActive ? "View pickups" : "Confirm & plan pickups",
                            symbol: "sparkles", disabled: store.backendBusy, id: "plan-pickups"
                        ) {
                            Task {
                                if store.runActive {
                                    router.sheet = .run
                                } else if store.isBackend && location.selection == nil && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                                    router.sheet = .location
                                } else if await store.confirmCartAndPlan() {
                                    router.sheet = .run
                                }
                            }
                        }
                        Text("Confirm to reserve your items. Contact sellers in the next step.")
                            .rescueFont(12)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }.navigationTitle("Your cart").navigationBarTitleDisplayMode(.inline)
    }
}

struct PickupFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var pin: String?
    var body: some View {
        Group {
            if store.phase == .idle {
                planView
            } else if store.phase == .enroute {
                timelineView
            } else if store.phase == .finished {
                ProgressView("Your impact is ready")
            } else {
                handoffView
            }
        }.navigationTitle(store.phase == .idle ? "Pickup plan" : "Pickup trip")
            .navigationBarTitleDisplayMode(.inline)
    }
    private var planView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PickupRouteMap(stops: store.plan?.stops ?? []).frame(
                    height: 240
                ).clipShape(RoundedRectangle(cornerRadius: 24))
                if let plan = store.plan, !plan.stops.isEmpty {
                    Text(plan.allConfirmed ? "ALL CONFIRMED" : "SMART PICKUP PLAN").rescueFont(
                        13, .semibold
                    ).foregroundStyle(Theme.sage)
                    Text(plan.allConfirmed ? "You're ready to go" : plan.stops.contains { $0.status == .waiting } ? "Requests sent" : "Your pickup route").rescueFont(26, .semibold)
                    Text("\(plan.stops.count) stops · optimized for distance and pickup windows")
                        .rescueFont(14).foregroundStyle(Theme.secondary)
                    if plan.stops.allSatisfy({ $0.status == .unconfirmed }) {
                        Text("Want a different order? Move stops before sending requests.")
                            .rescueFont(13).foregroundStyle(Theme.secondary)
                        ScrollView(.horizontal, showsIndicators: false) { HStack {
                            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                                Menu {
                                    if index > 0 { Button("Move earlier") { Task { await store.movePickupStop(stop.id, by: -1) } } }
                                    if index + 1 < plan.stops.count { Button("Move later") { Task { await store.movePickupStop(stop.id, by: 1) } } }
                                } label: {
                                    Label("\(index + 1). \(stop.seller.firstName)", systemImage: "line.3.horizontal")
                                        .rescueFont(12, .semibold).padding(10).background(Theme.soft, in: Capsule())
                                }.disabled(store.backendBusy).accessibilityIdentifier("reorder-\(stop.id)")
                            }
                        } }
                    } else if !plan.allConfirmed {
                        Text("Each seller needs to confirm your pickup time. Open a chat below to check in; Start pickups appears once everyone confirms.")
                            .rescueFont(14).foregroundStyle(Theme.secondary)
                        if store.isBackend && plan.stops.contains(where: { stop in MockCatalog.sellers.contains(where: { $0.id == stop.seller.id }) }) {
                            Text("Sample sellers are fictional and cannot reply. Use a listing from another signed-in account to try real confirmations.")
                                .rescueFont(12).foregroundStyle(Theme.muted)
                        }
                    }
                    if let sellerID = store.counterSellerID {
                        let seller = store.seller(sellerID)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(seller.firstName) requested a later pickup.").rescueFont(
                                15, .semibold)
                            Text("Accept +9 min, or suggest +19 min. Later stops update together.")
                                .rescueFont(14).foregroundStyle(Theme.secondary)
                            HStack {
                                Button("Accept") {
                                    store.acceptCounter()
                                    Haptic.success()
                                }.buttonStyle(.borderedProminent).tint(Theme.ink).buttonBorderShape(
                                    .capsule
                                ).accessibilityIdentifier("accept-time")
                                Button("Alternative") { store.acceptCounter(alternative: true) }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }.padding(16).background(
                            Theme.apricotSoft, in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    PickupTimeline(stops: plan.stops)
                    HStack(spacing: 12) {
                        MetricCard(
                            value: Money.text(plan.totals.saved), label: "saved", color: Theme.save)
                        MetricCard(
                            value: String(format: "%.1f lb", plan.totals.pounds), label: "food saved")
                    }
                    Text("Pickup addresses are shared after the seller confirms.").rescueFont(12).foregroundStyle(
                        Theme.muted)
                } else {
                    EmptyState(
                        title: "Add food to your cart",
                        message: "Your cart needs an available item before planning.")
                }
            }.padding(20)
        }.safeAreaInset(edge: .bottom) {
            BottomAction {
                if store.plan?.allConfirmed == true {
                    PrimaryButton(
                        title: "Start pickups", symbol: "location.fill", color: Theme.deep,
                        id: "start-run"
                    ) {
                        Task {
                            if await store.beginPickups() {
                                router.tab = .map
                                router.sheet = nil
                                Haptic.success()
                            }
                        }
                    }
                } else {
                    PrimaryButton(
                        title: store.coordinating
                            ? "Messaging sellers…"
                            : store.counterSellerID != nil
                                ? "Waiting on 1 seller"
                                : store.plan?.stops.contains(where: { $0.status == .waiting }) == true
                                    ? "Waiting for seller confirmations" : "Send pickup requests",
                        disabled: store.coordinating || store.backendBusy || store.counterSellerID != nil
                            || store.plan?.stops.contains(where: { $0.status == .unconfirmed }) != true
                            || store.plan?.stops.isEmpty != false, id: "coordinate"
                    ) {
                        Task {
                            await store.coordinate()
                            Haptic.success()
                        }
                    }
                }
            }
        }
    }
    private var timelineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PickupRouteMap(stops: store.plan?.stops ?? []).frame(
                    height: 200
                ).clipShape(RoundedRectangle(cornerRadius: 24))
                Text("Pickup trip · stop \(store.stopIndex + 1) of \(store.plan?.stops.count ?? 0)")
                    .rescueFont(22, .semibold)
                PickupTimeline(stops: store.plan?.stops ?? [], allowDelay: true)
                Text(store.isBackend ? "Use Directions to navigate, then mark your arrival below." : "Arrival is simulated for this demo.").rescueFont(
                    13
                ).foregroundStyle(Theme.muted)
            }.padding(20)
        }.safeAreaInset(edge: .bottom) {
            BottomAction {
                PrimaryButton(
                    title:
                        (store.isBackend ? "I’ve arrived at " : "Simulate arrival at ") + "\(store.currentStop?.seller.firstName ?? "seller")'s",
                    symbol: "location", id: "arrive"
                ) {
                    store.arrive()
                    Haptic.tap()
                }
            }
        }
    }
    @ViewBuilder private var handoffView: some View {
        if let stop = store.currentStop {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.isBackend, let location = stop.privateLocation,
                        location.cacheUntil > Date().timeIntervalSince1970 * 1000
                    {
                        Text(location.address).rescueFont(16, .semibold)
                        Text(location.instructions).rescueFont(14).foregroundStyle(Theme.secondary)
                    }
                    switch store.phase {
                    case .arrived, .waiting:
                        Label(
                            store.isBackend ? "Pickup with \(stop.seller.firstName)" : "Demo pickup spot · \(stop.seller.area)",
                            systemImage: "mappin.and.ellipse"
                        ).rescueFont(13, .semibold).foregroundStyle(Theme.sage)
                        Text("You've arrived").rescueFont(28, .semibold)
                        SellerRow(seller: stop.seller)
                        ForEach(stop.items) { item in HandoffItem(item: item) }
                        Button {
                            router.chat(stop.seller.id)
                        } label: {
                            Label("Message \(stop.seller.firstName)", systemImage: "bubble.left")
                                .rescueFont(16, .semibold)
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    case .verifying:
                        Text("\(stop.seller.firstName) handed it over").rescueFont(13, .semibold)
                            .foregroundStyle(Theme.sage)
                        Text("Does everything look right?").rescueFont(24, .semibold)
                        ForEach(stop.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                FoodPhoto(name: item.image).frame(height: 175).clipShape(
                                    RoundedRectangle(cornerRadius: 16))
                                Text(item.name).rescueFont(16, .semibold)
                                Text(
                                    "Listed · \(ListingTimestamp.display(item.updated)) · inspect the item at pickup"
                                )
                                .rescueFont(12).foregroundStyle(Theme.secondary)
                            }
                        }
                        Text("Demo reference photo. This is not a newly captured pickup photo.")
                            .rescueFont(12).foregroundStyle(Theme.muted)
                        Button(role: .destructive) {
                            store.reportIssue()
                        } label: {
                            Label("Report issue · skip this pickup", systemImage: "flag")
                                .rescueFont(15, .semibold)
                        }.accessibilityIdentifier("report-issue")
                    case .payment, .paying:
                        HStack(alignment: .firstTextBaseline) {
                            Text("Pay \(stop.seller.firstName)").rescueFont(24, .semibold)
                            Spacer()
                            Text("You save \(Money.text(stop.totals.saved))").rescueFont(
                                14, .semibold
                            ).foregroundStyle(Theme.save)
                        }
                        ForEach(stop.items) { item in HandoffItem(item: item) }
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(Money.text(stop.totals.pay)).monospacedDigit().fontWeight(
                                .semibold)
                        }.rescueFont(20).padding(16).card(radius: 16)
                        Text("Visa •• 4021 · mock payment method · no fees").rescueFont(13)
                            .foregroundStyle(Theme.muted)
                        Text("Demo payment — no money is charged.").rescueFont(14, .semibold)
                            .foregroundStyle(Theme.sage)
                    case .rescued:
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark").rescueFont(30, .bold).foregroundStyle(
                                Theme.paper
                            ).frame(width: 72, height: 72).background(Theme.sage, in: Circle())
                            Text("Picked up").rescueFont(30, .bold)
                            Text("You saved \(Money.text(stop.totals.saved))").rescueFont(
                                20, .semibold
                            ).foregroundStyle(Theme.save)
                            Text("\(String(format: "%.1f", stop.totals.pounds)) lb kept in use")
                                .rescueFont(14).foregroundStyle(Theme.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40).accessibilityIdentifier(
                            "pickup-success")
                    default: EmptyView()
                    }
                }.padding(20)
            }.safeAreaInset(edge: .bottom) {
                BottomAction {
                    if store.isBackend, let location = stop.privateLocation,
                        location.cacheUntil > Date().timeIntervalSince1970 * 1000
                    {
                        Text(location.address).rescueFont(16, .semibold)
                        Text(location.instructions).rescueFont(14).foregroundStyle(Theme.secondary)
                    }
                    switch store.phase {
                    case .arrived:
                        PrimaryButton(title: "I'm Here", id: "im-here") {
                            Task { await store.announceArrival() }
                        }
                    case .waiting:
                        PrimaryButton(
                            title: "\(stop.seller.firstName) is coming out…", disabled: true
                        ) {}
                    case .verifying:
                        PrimaryButton(title: "Looks good", id: "verify-pickup") {
                            store.verify()
                            Haptic.tap()
                        }
                    case .payment:
                        PrimaryButton(title: "Pay \(Money.text(stop.totals.pay))", id: "pay") {
                            Task {
                                await store.pay()
                                Haptic.success()
                            }
                        }
                    case .paying:
                        HStack {
                            ProgressView()
                            Text("Processing demo payment…").rescueFont(16)
                        }.frame(height: 54)
                    case .rescued:
                        PrimaryButton(
                            title: store.stopIndex + 1 == store.plan?.stops.count
                                ? "See your impact" : "Next pickup", color: Theme.deep,
                            id: "continue-run"
                        ) { store.continueRun() }
                    default: EmptyView()
                    }
                }
            }
        }
    }
}

private struct HandoffItem: View {
    let item: Listing
    var body: some View {
        HStack(spacing: 12) {
            FoodPhoto(name: item.image).frame(width: 58, height: 58).clipShape(
                RoundedRectangle(cornerRadius: 12))
            Text(item.name).rescueFont(15, .medium)
            Spacer()
            Text(Money.text(item.price)).rescueFont(17, .semibold).monospacedDigit()
        }.padding(10).card(radius: 18)
    }
}

struct PickupTimeline: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    let stops: [PickupStop]
    var allowDelay = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 12) {
                    Text(stop.time).rescueFont(16, .semibold).monospacedDigit().frame(width: 46)
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(
                                stop.status == .confirmed || stop.status == .paid
                                    ? Theme.sage : Theme.ink
                            ).frame(width: 24, height: 24)
                            if stop.status == .paid || stop.status == .confirmed {
                                Image(systemName: "checkmark").font(.caption2.bold())
                                    .foregroundStyle(Theme.paper)
                            } else {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(
                                    Theme.paper)
                            }
                        }
                        if index < stops.count - 1 {
                            Rectangle().fill(Theme.line).frame(width: 2, height: 45)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "\(stop.seller.firstName) · \(stop.items.map { $0.name.replacingOccurrences(of: "Organic ", with: "").replacingOccurrences(of: "Unopened ", with: "") }.joined(separator: ", "))"
                        ).rescueFont(16, .semibold)
                        Text("Pickup stop \(index + 1) · \(Money.text(stop.totals.pay))").rescueFont(13)
                            .foregroundStyle(Theme.secondary)
                        if store.phase == .idle {
                            Text(stop.status == .confirmed ? "Confirmed" : stop.status == .waiting ? "Waiting for seller" : "Not requested yet")
                                .rescueFont(12, .semibold).foregroundStyle(stop.status == .confirmed ? Theme.save : Theme.secondary)
                            if stop.status != .unconfirmed {
                                Button("Message \(stop.seller.firstName)") { router.chat(stop.seller.id) }
                                    .rescueFont(13, .semibold).foregroundStyle(Theme.save)
                            }
                        }
                        if stop.status == .skipped {
                            Text("Issue reported · no charge").rescueFont(12).foregroundStyle(
                                Theme.apricot)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if allowDelay && index >= store.stopIndex && stop.status != .paid
                        && stop.status != .skipped
                    {
                        Button("+10 min") { store.delayStop(stop.id) }.rescueFont(12, .semibold)
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                }.padding(.bottom, 10).opacity(
                    stop.status == .paid || stop.status == .skipped ? 0.55 : 1)
            }
        }
    }
}

struct LivePickupCard: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let stop = store.currentStop {
            HStack(spacing: 12) {
                FoodPhoto(name: stop.items.first?.image ?? "straw").frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next · \(stop.seller.firstName)").rescueFont(15, .semibold)
                    Text("\(stop.time) · \(stop.items.count) items · stop \(store.stopIndex + 1)")
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").foregroundStyle(Theme.muted)
            }.padding(12).card(radius: 28).shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 6)
                .foregroundStyle(Theme.ink).accessibilityIdentifier("active-run")
        }
    }
}

struct FinaleView: View {
    @Environment(AppStore.self) private var store
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pickups complete").rescueFont(15, .medium).foregroundStyle(Theme.butter)
                .padding(.top, 40)
            Text(Money.text(store.runImpact.saved)).rescueFont(64, .bold).monospacedDigit()
                .minimumScaleFactor(0.6).accessibilityIdentifier("impact-saved")
            Text("saved tonight").rescueFont(17).foregroundStyle(Theme.paper.opacity(0.7))
            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Text("\(store.runImpact.pounds, specifier: "%.1f") lb").rescueFont(
                        32, .semibold
                    ).accessibilityIdentifier("impact-pounds")
                    Text("food kept in use").rescueFont(14).foregroundStyle(
                        Theme.paper.opacity(0.6))
                }
                VStack(alignment: .leading) {
                    Text("1").rescueFont(32, .semibold)
                    Text("trip").rescueFont(14).foregroundStyle(Theme.paper.opacity(0.6))
                }
            }.padding(.top, 28)
            Spacer()
            Image(systemName: "leaf").foregroundStyle(Theme.butter)
            Text("Better prices.\nLess waste.\nOne trip.").rescueFont(30, .semibold)
            PrimaryButton(
                title: "Done", color: Theme.bone, foreground: Theme.ink, id: "impact-done",
                action: onDone
            ).padding(.top, 24)
        }.padding(28).foregroundStyle(Theme.paper).frame(
            maxWidth: .infinity, maxHeight: .infinity, alignment: .leading
        ).background(Theme.deep).preferredColorScheme(.dark).interactiveDismissDisabled()
    }
}
