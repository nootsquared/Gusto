import SwiftUI

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
    private var groups: [PickupStop] { PickupPlanner.build(items: store.cartItems).stops }
    var body: some View {
        Group {
            if store.cart.isEmpty {
                VStack {
                    EmptyState(
                        title: "Nothing reserved yet", message: "Good food is waiting nearby.",
                        symbol: "bag")
                    PrimaryButton(title: "Discover food") { router.sheet = nil }.padding(20)
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
                            title: store.runActive ? "View rescue run" : "Plan My Pickups",
                            symbol: "sparkles", id: "plan-pickups"
                        ) {
                            if !store.runActive { store.makePlan() }
                            router.sheet = .run
                        }
                        Text("No charge until pickup · demo payments only").rescueFont(12)
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
    @State private var mode: RouteMode = .fastest
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
                RescueMap(items: [], stops: store.plan?.stops ?? [], selectedID: $pin).frame(
                    height: 240
                ).clipShape(RoundedRectangle(cornerRadius: 24))
                if let plan = store.plan, !plan.stops.isEmpty {
                    Text(plan.allConfirmed ? "ALL CONFIRMED" : "SMART PICKUP PLAN").rescueFont(
                        13, .semibold
                    ).foregroundStyle(Theme.sage)
                    Text(
                        mode == .fastest
                            ? "Your fastest pickup route"
                            : mode == .shortest
                                ? "Your shortest pickup route" : "Your best pickup times"
                    ).rescueFont(26, .semibold)
                    Text(
                        "\(plan.stops.count) stops · \(plan.elapsed) min · \(String(format: "%.1f", plan.distance)) mi"
                    ).rescueFont(15).foregroundStyle(Theme.secondary)
                    Picker("Route preference", selection: $mode) {
                        ForEach(RouteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(
                        store.coordinating || plan.stops.contains { $0.status != .unconfirmed }
                    )
                    .onChange(of: mode) { _, value in store.makePlan(mode: value) }
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
                    Text("Demo estimates · fixed pickup area").rescueFont(12).foregroundStyle(
                        Theme.muted)
                } else {
                    EmptyState(
                        title: "Reserve food first",
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
                        if store.startRun() {
                            router.tab = .map
                            router.sheet = nil
                            Haptic.success()
                        }
                    }
                } else {
                    PrimaryButton(
                        title: store.coordinating
                            ? "Messaging sellers…"
                            : store.counterSellerID != nil
                                ? "Waiting on 1 seller"
                                : "Coordinate All \(store.plan?.stops.count ?? 0)",
                        disabled: store.coordinating || store.counterSellerID != nil
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
                RescueMap(items: [], stops: store.plan?.stops ?? [], selectedID: $pin).frame(
                    height: 200
                ).clipShape(RoundedRectangle(cornerRadius: 24))
                Text("Pickup trip · stop \(store.stopIndex + 1) of \(store.plan?.stops.count ?? 0)")
                    .rescueFont(22, .semibold)
                PickupTimeline(stops: store.plan?.stops ?? [], allowDelay: true)
                Text("Arrival is simulated for this demo. No location access is used.").rescueFont(
                    13
                ).foregroundStyle(Theme.muted)
            }.padding(20)
        }.safeAreaInset(edge: .bottom) {
            BottomAction {
                PrimaryButton(
                    title:
                        "Simulate arrival at \(store.currentStop?.seller.firstName ?? "seller")'s",
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
                            "Demo pickup spot · \(stop.seller.area)",
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
                                Text("Listed · \(item.updated) · inspect the item at pickup")
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
                        Text("\(stop.seller.area) · \(Money.text(stop.totals.pay))").rescueFont(13)
                            .foregroundStyle(Theme.secondary)
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
