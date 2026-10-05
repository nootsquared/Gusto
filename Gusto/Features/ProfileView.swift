import Charts
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    private var liveListingCount: Int {
        store.ownListings.filter(\.available).count + (store.isBackend ? 0 : store.catalog.filter { $0.id == "my-granola" }.count)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    AccountAvatar(size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.profileName).gustoFont(26, .bold)
                        Text(
                            store.isBackend
                                ? "\(store.receipts.count) completed purchases"
                                : "4.9 · 24 pickups · Student verified"
                        ).gustoFont(13).foregroundStyle(
                            Theme.secondary)
                    }
                }
                Button {
                    router.sheet = .profile(.impact)
                } label: {
                    ImpactHero(totals: store.impact, earnings: store.earnings)
                }.buttonStyle(.plain)
                Button {
                    router.sheet = .profile(.referrals)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gift")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Give 10%, get 10%").gustoFont(15, .semibold)
                            Text("Invite a friend to their first pickup").gustoFont(13)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(16).foregroundStyle(Theme.ink).background(
                        Theme.butterSoft, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                VStack(spacing: 0) {
                    profileRow(
                        "My Listings", "tag", .listings,
                        detail:
                            "\(liveListingCount) live"
                    )
                    profileRow("Purchases & Sales", "receipt", .purchases)
                    profileRow("Saved", "heart", .saved, detail: "\(store.savedIDs.count)")
                    profileRow(
                        "Alerts & follows", "bell", .alerts,
                        detail: store.isBackend ? "Preferences" : "5")
                    profileRow("Payment", "creditcard", .payment, detail: "Demo only")
                    profileRow(
                        "Verification", "checkmark.shield", .verification, detail: "Unavailable")
                    profileRow("Referrals", "gift", .referrals, detail: "Give 10%")
                    profileRow("Settings", "gearshape", .settings, last: true)
                }.padding(.horizontal, 16).card(radius: 20)
            }.padding(20)
        }.background(Theme.ivory).foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar)
    }
    private func profileRow(
        _ title: String, _ icon: String, _ panel: ProfilePanel, detail: String = "",
        last: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                router.sheet = .profile(panel)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 20)
                    Text(title)
                    Spacer(minLength: 0)
                    Text(detail).gustoFont(13).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").gustoFont(13).foregroundStyle(Theme.muted)
                }.gustoFont(16).padding(.vertical, 16).foregroundStyle(Theme.ink)
            }.buttonStyle(.plain)
            if !last { Divider().overlay(Theme.line) }
        }
    }
}

struct ImpactHero: View {
    let totals: Totals
    let earnings: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your impact").gustoFont(13)
                Spacer()
                Image(systemName: "chevron.right")
            }.foregroundStyle(Theme.paper.opacity(0.7))
            Text("\(totals.pounds, specifier: "%.1f") lb").gustoFont(46, .bold)
                .monospacedDigit()
            Text("food kept in use").gustoFont(15).foregroundStyle(Theme.paper.opacity(0.7))
            MonthlyChart(extra: totals.pounds, compact: true).frame(height: 42).padding(.top, 8)
            Divider().overlay(Theme.paper.opacity(0.15)).padding(.vertical, 6)
            HStack {
                VStack(alignment: .leading) {
                    Text(Money.text(totals.saved)).gustoFont(20, .semibold)
                    Text("saved").gustoFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(Money.text(earnings)).gustoFont(20, .semibold)
                    Text("earned").gustoFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("\(totals.count)").gustoFont(20, .semibold)
                    Text("items").gustoFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
            }.monospacedDigit()
        }.padding(20).foregroundStyle(Theme.paper).background(
            Theme.deep, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct MonthlyChart: View {
    @Environment(AppStore.self) private var store
    let extra: Double
    var compact = false
    private var months: [(String, Double)] {
        if store.isBackend {
            return store.monthly.sorted { $0.month < $1.month }.map {
                ($0.month, Double($0.grams) / 453.59237)
            }
        }
        return [("This demo", extra)]
    }
    var body: some View {
        Chart(Array(months.enumerated()), id: \.offset) { _, month in
            BarMark(x: .value("Month", month.0), y: .value("Pounds", month.1))
                .foregroundStyle(
                    month.0 == "Oct"
                        ? (compact ? Theme.butter : Theme.deep)
                        : (compact ? Theme.paper.opacity(0.2) : Theme.soft)
                ).cornerRadius(compact ? 4 : 8)
        }.chartYAxis(.hidden).chartXAxis(compact ? .hidden : .automatic).accessibilityLabel(
            "Estimated food saved by month"
        ).accessibilityValue(
            months.map { "\($0.0): \(String(format: "%.1f", $0.1)) pounds" }.joined(separator: ", ")
        )
    }
}

struct ProfilePanelView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("useLiveMap") private var useLiveMap = false
    @AppStorage("smartAlerts") private var smartAlerts = true
    let panel: ProfilePanel
    private let invite = "gusto-demo://invite/priya"
    var body: some View {
        Group {
            switch panel {
            case .impact:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("SINCE MAY").gustoFont(13, .semibold).foregroundStyle(Theme.sage)
                        Text("\(store.impact.pounds, specifier: "%.1f") lb").gustoFont(
                            56, .bold)
                        Text("food kept in use").gustoFont(17).foregroundStyle(Theme.secondary)
                        HStack {
                            MetricCard(
                                value: Money.text(store.impact.saved), label: "saved")
                            MetricCard(value: "\(store.receipts.count)", label: "pickups")
                            MetricCard(value: "\(store.impact.count)", label: "items")
                        }
                        Text("By month").gustoFont(20, .semibold)
                        MonthlyChart(extra: store.impact.pounds).frame(height: 190)
                        Text(
                            "Your past pickups, grouped by month. Weights are seller-reported estimates."
                        ).gustoFont(14).foregroundStyle(Theme.secondary).padding(16).background(
                            Theme.bone, in: RoundedRectangle(cornerRadius: 16))
                    }.padding(20)
                }
            case .referrals:
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Give 10%, get 10%").gustoFont(28, .bold)
                        Text("Off your next purchase — for both of you.").gustoFont(15)
                            .foregroundStyle(Theme.secondary)
                        if let qr = QRCode.image(invite) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(
                                width: 180, height: 180
                            ).padding(20).card(radius: 24).accessibilityLabel(
                                "Demo invitation QR code")
                        }
                        Text("Demo invitation · no referral is redeemed").gustoFont(12)
                            .foregroundStyle(Theme.muted)
                        Button {
                            UIPasteboard.general.string = invite
                            store.notice = "Demo invite copied"
                        } label: {
                            Label("Copy invite", systemImage: "doc.on.doc")
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        Text("I kept \(Int(store.impact.pounds)) lb of food in use.")
                            .gustoFont(24, .semibold).foregroundStyle(Theme.paper).frame(
                                maxWidth: .infinity, alignment: .leading
                            ).padding(20).background(
                                Theme.deep, in: RoundedRectangle(cornerRadius: 24))
                        ShareLink(item: "Join my Gusto demo: \(invite)") {
                            Label("Share", systemImage: "square.and.arrow.up").frame(
                                maxWidth: .infinity
                            ).padding(16)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    }.padding(20)
                }
            case .alerts:
                Form {
                    Section("Alerts") {
                        Toggle(
                            "Smart alerts",
                            isOn: store.isBackend
                                ? Binding(
                                    get: { store.preferences?.smartAlerts ?? false },
                                    set: { store.updateSmartAlerts($0) }) : $smartAlerts)
                        if store.isBackend && SessionController.shared.isLocalBackend {
                            Text(
                                "Push delivery is not connected. Preferences and follows are saved to this account."
                            ).font(.footnote)
                        } else {
                            ForEach(
                                [
                                    "Strawberries for $2.50 were listed nearby.",
                                    "Your pickup route starts in 20 minutes.",
                                    "Nina reconfirmed freshness.",
                                    "An item you saved dropped to $3.",
                                ], id: \.self
                            ) { Text($0).gustoFont(15) }
                        }
                    }
                    Section("Following") {
                        if store.isBackend {
                            ForEach(
                                ["Produce", "Breakfast", "Bakery", "Dairy", "Snacks"], id: \.self
                            ) { category in
                                Toggle(
                                    category,
                                    isOn: Binding(
                                        get: {
                                            store.follows.contains {
                                                $0.kind == "category" && $0.target == category
                                            }
                                        },
                                        set: {
                                            store.setFollow(
                                                kind: "category", target: category, enabled: $0)
                                        }))
                            }
                        } else {
                            ForEach(
                                ["Strawberries", "Breakfast", "Maya R.", "Under $3", "Bakery"],
                                id: \.self
                            ) { Text($0) }
                        }
                    }
                    Section {
                        Text("Demo preferences only; no push notifications are sent.").font(
                            .footnote)
                    }
                }.scrollContentBackground(.hidden)
            case .listings:
                let own =
                    store.isBackend
                    ? store.ownListings : store.ownListings + store.catalog.filter { $0.id == "my-granola" }
                if own.isEmpty {
                    VStack {
                        EmptyState(
                            title: "No listings yet", message: "Scan an item, then choose Sell this item."
                        )
                        Button("Scan food") {
                            router.sheet = nil
                            router.tab = .scan
                        }.buttonStyle(.borderedProminent).padding()
                    }
                } else {
                    List(own) {
                        ListingRow(item: $0, showAdd: false).listRowBackground(Theme.ivory)
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            case .purchases:
                let history = store.receipts + store.sales
                if history.isEmpty {
                    EmptyState(
                        title: "No pickups yet",
                        message: "Complete a pickup to see your receipts.", symbol: "receipt")
                } else {
                    List {
                        ForEach(history.indices, id: \.self) { index in
                            let receipt = history[index]
                            VStack(alignment: .leading, spacing: 5) {
                                Text(receipt.seller.name).font(.headline)
                                Text(receipt.items.map(\.name).joined(separator: ", ")).font(
                                    .subheadline)
                                Text(
                                    "Demo paid \(Money.text(receipt.paid)) · saved \(Money.text(receipt.totals.saved))"
                                ).font(.footnote).foregroundStyle(Theme.save)
                            }.listRowBackground(Theme.ivory)
                        }
                        if store.morePurchases {
                            Button("Load more purchases") {
                                Task { await store.loadHistory(selling: false) }
                            }.disabled(store.historyLoading)
                        }
                        if store.moreSales {
                            Button("Load more sales") {
                                Task { await store.loadHistory(selling: true) }
                            }.disabled(store.historyLoading)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            case .saved:
                let items = store.catalog.filter { store.savedIDs.contains($0.id) }
                if items.isEmpty {
                    EmptyState(
                        title: "Nothing saved yet",
                        message: "Tap the heart in a listing to save it.", symbol: "heart")
                } else {
                    List(items) { ListingRow(item: $0).listRowBackground(Theme.ivory) }.listStyle(
                        .plain
                    ).scrollContentBackground(.hidden)
                }
            case .payment:
                Form {
                    Section("Demo payment method") {
                        Label("Visa •• 4021", systemImage: "creditcard")
                        Text(
                            "This is mock card information. No actual payment method is stored and no charges are made."
                        ).font(.footnote)
                    }
                }.scrollContentBackground(.hidden)
            case .verification:
                Form {
                    Section("Demo profile") {
                        Label("Identity verification unavailable", systemImage: "checkmark.shield")
                        Label("Student verification unavailable", systemImage: "graduationcap")
                        Text("Verification needs a future trusted provider.").font(.footnote)
                    }
                }.scrollContentBackground(.hidden)
            case .settings:
                Form {
                    Section("Demo") {
                        Toggle("Live maps for pickup routes", isOn: $useLiveMap)
                        Text(
                            "Off uses the source design's offline map. On loads Apple's map tiles; seller coordinates remain fictional."
                        ).font(.footnote)
                        Button(
                            store.isBackend ? "Clear device cache and refresh" : "Reset demo",
                            role: .destructive
                        ) {
                            store.resetDemo()
                            router.sheet = nil
                            router.tab = .discover
                        }
                    }
                    #if DEBUG
                        if store.isBackend {
                            Section("Local demo accounts") {
                                ForEach(SessionController.shared.accounts, id: \.userId) {
                                    session in
                                    Button(
                                        session.userId
                                            + (session.userId == store.accountID ? " ✓" : "")
                                    ) {
                                        do {
                                            try SessionController.shared.select(session.userId)
                                            let repository = try SessionController.shared
                                                .repository()
                                            router.sheet = nil
                                            router.tab = .discover
                                            Task { await store.connect(repository) }
                                        } catch { store.notice = error.localizedDescription }
                                    }.accessibilityIdentifier("account-\(session.userId)")
                                }
                                Button("Refresh provisioned accounts") {
                                    Task {
                                        do {
                                            try await SessionController.shared.loadDemoAccounts()
                                            await store.connect(
                                                try SessionController.shared.repository())
                                        } catch { store.notice = error.localizedDescription }
                                    }
                                }
                            }
                        }
                    #endif
                    if store.isBackend && !SessionController.shared.isLocalBackend {
                        Section("Account") {
                            Button("Sign out", role: .destructive) {
                                SessionController.shared.signOut()
                                store.disconnectBackend()
                                router.sheet = nil
                                router.tab = .discover
                            }.accessibilityIdentifier("sign-out")
                        }
                    }
                    Section("About") {
                        Text("Gusto · Native iPhone demo")
                        Text("SwiftUI · iOS 17+")
                        Text(
                            store.isBackend
                                ? "Account data persists on the server. Clearing this device’s cache does not reset shared data."
                                : "Fixture activity resets when the app restarts."
                        ).font(.footnote)
                    }
                }.scrollContentBackground(.hidden)
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private var title: String {
        switch panel {
        case .impact: "Your impact"
        case .referrals: "Referrals"
        case .alerts: "Alerts & follows"
        case .listings: "My Listings"
        case .purchases: "Purchases & Sales"
        case .saved: "Saved"
        case .payment: "Payment"
        case .verification: "Verification"
        case .settings: "Settings"
        }
    }
}

private enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
            let cg = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
