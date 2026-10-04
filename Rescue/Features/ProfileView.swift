import Charts
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    FoodPhoto(name: "profile").frame(width: 72, height: 72).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Priya S.", systemImage: "checkmark.seal.fill").rescueFont(26, .bold)
                        Text("4.9 · 24 pickups · Student verified").rescueFont(13).foregroundStyle(
                            Theme.secondary)
                    }
                }
                Button {
                    router.sheet = .profile(.impact)
                } label: {
                    ImpactHero(totals: store.impact)
                }.buttonStyle(.plain)
                Button {
                    router.sheet = .profile(.referrals)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gift")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Give 10%, get 10%").rescueFont(15, .semibold)
                            Text("Invite a friend to their first rescue").rescueFont(13)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(16).foregroundStyle(Theme.ink).background(
                        Theme.butterSoft, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                VStack(spacing: 0) {
                    profileRow(
                        "My Listings", "tag", .listings,
                        detail: "\(store.catalog.filter { $0.id == "my-granola" }.count) live")
                    profileRow("Purchases & Sales", "receipt", .purchases)
                    profileRow("Saved", "heart", .saved, detail: "\(store.savedIDs.count)")
                    profileRow("Alerts & follows", "bell", .alerts, detail: "5")
                    profileRow("Payment", "creditcard", .payment, detail: "Visa •• 4021")
                    profileRow(
                        "Verification", "checkmark.shield", .verification, detail: "ID · Student")
                    profileRow("Referrals", "gift", .referrals, detail: "Give 10%")
                    profileRow("Settings", "gearshape", .settings, last: true)
                }.padding(.horizontal, 16).card(radius: 20)
            }.padding(20)
        }.background(Theme.ivory).foregroundStyle(Theme.ink).navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
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
                    Text(detail).rescueFont(13).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").rescueFont(13).foregroundStyle(Theme.muted)
                }.rescueFont(16).padding(.vertical, 16).foregroundStyle(Theme.ink)
            }.buttonStyle(.plain)
            if !last { Divider().overlay(Theme.line) }
        }
    }
}

struct ImpactHero: View {
    let totals: Totals
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your impact").rescueFont(13)
                Spacer()
                Image(systemName: "chevron.right")
            }.foregroundStyle(Theme.paper.opacity(0.7))
            Text("\(31.4 + totals.pounds, specifier: "%.1f") lb").rescueFont(46, .bold)
                .monospacedDigit()
            Text("food kept in use").rescueFont(15).foregroundStyle(Theme.paper.opacity(0.7))
            MonthlyChart(extra: totals.pounds, compact: true).frame(height: 42).padding(.top, 8)
            Divider().overlay(Theme.paper.opacity(0.15)).padding(.vertical, 6)
            HStack {
                VStack(alignment: .leading) {
                    Text(Money.text(14600 + totals.saved)).rescueFont(20, .semibold)
                    Text("saved").rescueFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("$82").rescueFont(20, .semibold)
                    Text("earned").rescueFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("\(46 + totals.count)").rescueFont(20, .semibold)
                    Text("items").rescueFont(13).foregroundStyle(Theme.paper.opacity(0.6))
                }
            }.monospacedDigit()
        }.padding(20).foregroundStyle(Theme.paper).background(
            Theme.deep, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct MonthlyChart: View {
    let extra: Double
    var compact = false
    private var months: [(String, Double)] {
        [
            ("May", 3.1), ("Jun", 4.6), ("Jul", 3.8), ("Aug", 6.2), ("Sep", 8.9),
            ("Oct", 4.8 + extra),
        ]
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
            "Estimated food rescued by month"
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
    private let invite = "rescue-demo://invite/priya"
    var body: some View {
        Group {
            switch panel {
            case .impact:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("SINCE MAY").rescueFont(13, .semibold).foregroundStyle(Theme.sage)
                        Text("\(31.4 + store.impact.pounds, specifier: "%.1f") lb").rescueFont(
                            56, .bold)
                        Text("food kept in use").rescueFont(17).foregroundStyle(Theme.secondary)
                        HStack {
                            MetricCard(
                                value: Money.text(14600 + store.impact.saved), label: "saved")
                            MetricCard(value: "\(12 + store.receipts.count)", label: "rescues")
                            MetricCard(value: "\(46 + store.impact.count)", label: "items")
                        }
                        Text("By month").rescueFont(20, .semibold)
                        MonthlyChart(extra: store.impact.pounds).frame(height: 190)
                        Text(
                            "Mostly breakfast and produce — you're best at rescuing things on your way home. Weights are seller-reported estimates."
                        ).rescueFont(14).foregroundStyle(Theme.secondary).padding(16).background(
                            Theme.bone, in: RoundedRectangle(cornerRadius: 16))
                    }.padding(20)
                }
            case .referrals:
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Give 10%, get 10%").rescueFont(28, .bold)
                        Text("Off your next rescue — for both of you.").rescueFont(15)
                            .foregroundStyle(Theme.secondary)
                        if let qr = QRCode.image(invite) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(
                                width: 180, height: 180
                            ).padding(20).card(radius: 24).accessibilityLabel(
                                "Demo invitation QR code")
                        }
                        Text("Demo invitation · no referral is redeemed").rescueFont(12)
                            .foregroundStyle(Theme.muted)
                        Button {
                            UIPasteboard.general.string = invite
                            store.notice = "Demo invite copied"
                        } label: {
                            Label("Copy invite", systemImage: "doc.on.doc")
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        Text("I kept \(Int(31.4 + store.impact.pounds)) lb of food in use.")
                            .rescueFont(24, .semibold).foregroundStyle(Theme.paper).frame(
                                maxWidth: .infinity, alignment: .leading
                            ).padding(20).background(
                                Theme.deep, in: RoundedRectangle(cornerRadius: 24))
                        ShareLink(item: "Join my Rescue demo: \(invite)") {
                            Label("Share", systemImage: "square.and.arrow.up").frame(
                                maxWidth: .infinity
                            ).padding(16)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    }.padding(20)
                }
            case .alerts:
                Form {
                    Section("Alerts") {
                        Toggle("Smart alerts", isOn: $smartAlerts)
                        ForEach(
                            [
                                "Strawberries for $2.50 were listed nearby.",
                                "Your pickup route starts in 20 minutes.",
                                "Nina reconfirmed freshness.", "An item you saved dropped to $3.",
                            ], id: \.self
                        ) { Text($0).rescueFont(15) }
                    }
                    Section("Following") {
                        ForEach(
                            ["Strawberries", "Breakfast", "Maya R.", "Under $3", "Bakery"],
                            id: \.self
                        ) { Text($0) }
                    }
                    Section {
                        Text("Demo preferences only; no push notifications are sent.").font(
                            .footnote)
                    }
                }.scrollContentBackground(.hidden)
            case .listings:
                let own = store.catalog.filter { $0.id == "my-granola" }
                if own.isEmpty {
                    VStack {
                        EmptyState(
                            title: "No listings yet", message: "Try the Sell tab's mock photo scan."
                        )
                        Button("List food") {
                            router.sheet = nil
                            router.tab = .sell
                        }.buttonStyle(.borderedProminent).padding()
                    }
                } else {
                    List(own) {
                        ListingRow(item: $0, showAdd: false).listRowBackground(Theme.ivory)
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            case .purchases:
                if store.receipts.isEmpty {
                    EmptyState(
                        title: "No pickups yet",
                        message: "Complete a rescue run to see your receipts.", symbol: "receipt")
                } else {
                    List(store.receipts.indices, id: \.self) { index in
                        let receipt = store.receipts[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(receipt.seller.name).font(.headline)
                            Text(receipt.items.map(\.name).joined(separator: ", ")).font(
                                .subheadline)
                            Text(
                                "Demo paid \(Money.text(receipt.paid)) · saved \(Money.text(receipt.totals.saved))"
                            ).font(.footnote).foregroundStyle(Theme.save)
                        }.listRowBackground(Theme.ivory)
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
                        Label("Identity verified", systemImage: "checkmark.seal.fill")
                        Label("Student verified", systemImage: "graduationcap")
                        Text("Verification badges are mock data for the demo.").font(.footnote)
                    }
                }.scrollContentBackground(.hidden)
            case .settings:
                Form {
                    Section("Demo") {
                        Toggle("Use live MapKit basemap", isOn: $useLiveMap)
                        Text(
                            "Off uses the source design's offline map. On loads Apple's map tiles; seller coordinates remain fictional."
                        ).font(.footnote)
                        Button("Reset demo", role: .destructive) {
                            store.resetDemo()
                            router.sheet = nil
                            router.tab = .discover
                        }
                    }
                    Section("About") {
                        Text("Rescue · Native iPhone demo")
                        Text("SwiftUI · iOS 17+")
                        Text(
                            "Mock data resets when the app restarts. Onboarding and preferences are saved locally."
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
