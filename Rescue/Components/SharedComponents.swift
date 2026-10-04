import SwiftUI

enum ListingTimestamp {
    static func display(_ value: String, now: Date = .now) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: value)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: value)
        }
        if let date {
            if abs(now.timeIntervalSince(date)) < 60 { return "Just now" }
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .full
            return relative.localizedString(for: date, relativeTo: now)
        }
        // Local fixtures already contain relative labels; never expose an unknown raw value.
        if value == "just now" { return "Just now" }
        if value == "yesterday" { return "Yesterday" }
        if value.range(of: #"^\d+[mh] ago$"#, options: .regularExpression) != nil {
            return value
        }
        return "Date unavailable"
    }
}

struct FoodPhoto: View {
    let name: String
    @State private var remoteImage: UIImage?
    var body: some View {
        GeometryReader { geometry in
            if name.hasPrefix("data:image/jpeg;base64,"),
                let data = Data(base64Encoded: String(name.dropFirst(23))),
                let image = UIImage(data: data)
            {
                Image(uiImage: image).resizable().scaledToFill().frame(
                    width: geometry.size.width, height: geometry.size.height
                ).clipped()
            } else if name.hasPrefix("/") || name.hasPrefix("http") {
                Group {
                    if let remoteImage {
                        Image(uiImage: remoteImage).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Theme.line
                            Image(systemName: "photo").foregroundStyle(Theme.muted)
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .task(id: name) {
                        remoteImage = nil
                        remoteImage = try? await ImagePipeline.shared.image(name)
                    }
            } else if UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill().frame(
                    width: geometry.size.width, height: geometry.size.height
                ).clipped()
            } else {
                ZStack {
                    Theme.line
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text("Photo unavailable").font(.caption2)
                    }.foregroundStyle(Theme.muted)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct AccountAvatar: View {
    @Environment(AppStore.self) private var store
    var size: CGFloat = 32
    var body: some View {
        Group {
            if let avatar = store.profileAvatar, !avatar.isEmpty {
                FoodPhoto(name: avatar)
            } else if !store.isBackend {
                FoodPhoto(name: "profile")
            } else {
                Text(String(store.profileName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.save).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.soft)
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}

struct Avatar: View {
    let seller: Seller
    var size: CGFloat = 36
    var body: some View {
        FoodPhoto(name: seller.image).frame(width: size, height: size).clipShape(Circle())
    }
}

struct FreshnessBadge: View {
    let freshness: Freshness
    var solid = false
    var showDot = false
    private var background: Color {
        solid
            ? Theme.paper.opacity(0.95)
            : freshness == .fresh
                ? Theme.soft : freshness == .good ? Theme.butterSoft : Theme.coralSoft
    }
    private var foreground: Color {
        freshness == .fresh
            ? Theme.deep
            : freshness == .good
                ? Color(red: 0.478, green: 0.373, blue: 0.114)
                : Color(red: 0.659, green: 0.251, blue: 0.184)
    }
    var body: some View {
        HStack(spacing: 4) {
            if showDot {
                Circle().fill(
                    freshness == .fresh
                        ? Theme.sage : freshness == .good ? Theme.butter : Theme.coral
                ).frame(width: 6, height: 6)
            }
            Text(freshness.rawValue)
        }.rescueFont(12, .semibold).foregroundStyle(foreground).padding(.horizontal, 8).padding(
            .vertical, 4
        ).background(background, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var color: Color = Theme.ink
    var foreground: Color = Theme.paper
    var disabled = false
    var id: String = ""
    let action: () -> Void
    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).multilineTextAlignment(.center)
            }.rescueFont(17, .semibold).frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(foreground).background(color, in: Capsule())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1)
            .accessibilityIdentifier(id)
    }
}

struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Text(title).rescueFont(14, .medium).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(selected ? Theme.paper : Theme.ink)
                .background(selected ? Theme.ink : Theme.paper, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.ink : Theme.line, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PriceLabel: View {
    let item: Listing
    var size: CGFloat = 20
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(Money.text(item.price)).rescueFont(size, .semibold).foregroundStyle(Theme.ink)
            Text(Money.text(item.retail)).strikethrough().rescueFont(13).foregroundStyle(
                Theme.muted)
            Text("\(item.discount)% off").rescueFont(13, .semibold).foregroundStyle(Theme.save)
        }.monospacedDigit()
    }
}

struct SellerRow: View {
    let seller: Seller
    var body: some View {
        HStack(spacing: 12) {
            Avatar(seller: seller, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(seller.name).rescueFont(15, .semibold)
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.sage)
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.butter)
                    Text(
                        String(
                            format: "%.1f · %d pickups · Responds %@", seller.rating,
                            seller.pickups, seller.responds))
                }.rescueFont(12).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct AddButton: View {
    @Environment(AppStore.self) private var store
    let item: Listing
    var body: some View {
        let inCart = store.cart.contains(item.id)
        Button {
            if store.addToCart(item.id) { Haptic.success() }
        } label: {
            Image(systemName: inCart ? "checkmark" : "plus").rescueFont(14, .semibold)
                .frame(width: 28, height: 28).foregroundStyle(inCart ? Theme.paper : Theme.ink)
                .background(inCart ? Theme.sage : Theme.paper, in: Circle())
                .shadow(color: Theme.ink.opacity(0.07), radius: 3, y: 2)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(
            inCart || store.runActive || store.backendBusy || !item.available
        )
        .accessibilityLabel(inCart ? "In cart: \(item.name)" : "Add \(item.name)")
        .accessibilityIdentifier("add-\(item.id)")
    }
}

/// The original price anchors the savings to retail, rather than suggesting a second discount.
struct ListingOffer: View {
    let item: Listing
    var priceSize: CGFloat = 17

    private var savings: some View {
        Text("\(item.discount)% less").rescueFont(12, .semibold).foregroundStyle(Theme.save)
    }
    private var distance: some View {
        Text("\(item.distance, specifier: "%.1f") mi")
            .rescueFont(12, .medium).foregroundStyle(Theme.secondary)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Money.text(item.price)).rescueFont(priceSize, .bold).foregroundStyle(Theme.ink)
                if item.retail > item.price {
                    Text(Money.text(item.retail)).strikethrough()
                        .rescueFont(12, .medium).foregroundStyle(Theme.muted)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if item.retail > item.price {
                        savings
                        Text("·").rescueFont(12).foregroundStyle(Theme.muted)
                    }
                    distance
                }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    if item.retail > item.price { savings }
                    distance
                }
            }
        }.monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Price \(Money.text(item.price)), retail \(Money.text(item.retail)), \(item.discount) percent below retail, \(String(format: "%.1f", item.distance)) miles away"
            )
    }
}

struct ListingTile: View {
    @Environment(AppRouter.self) private var router
    let item: Listing
    var width: CGFloat = 164
    var isDeal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                router.sheet = .listing(item.id)
            } label: {
                FoodPhoto(name: item.image).frame(width: width, height: width).clipShape(
                    RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityLabel("\(item.name), \(Money.text(item.price))")
                .accessibilityIdentifier("listing-\(item.id)")
                .overlay(alignment: .bottomTrailing) { AddButton(item: item).padding(2) }
                .overlay(alignment: .topLeading) {
                    if isDeal {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.save)
                            .frame(width: 30, height: 30)
                            .background(Theme.paper.opacity(0.96), in: Circle())
                            .shadow(color: Theme.deep.opacity(0.08), radius: 4, y: 2)
                            .padding(8)
                            .accessibilityLabel("Good deal")
                    }
                }
            Text(item.name).rescueFont(15, .semibold).lineLimit(1)
            ListingOffer(item: item)
        }.frame(width: width)
    }
}

struct ListingRow: View {
    @Environment(AppRouter.self) private var router
    let item: Listing
    var showAdd = true
    var identifierPrefix = "row"
    var body: some View {
        HStack(spacing: 12) {
            Button {
                router.sheet = .listing(item.id)
            } label: {
                HStack(spacing: 12) {
                    FoodPhoto(name: item.image).frame(width: 52, height: 52).clipShape(
                        RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).rescueFont(15, .semibold).lineLimit(1)
                        ListingOffer(item: item, priceSize: 15)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(Theme.ink).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("\(identifierPrefix)-\(item.id)")
            if showAdd { AddButton(item: item) }
        }.padding(.vertical, 8)
    }
}

struct MetricCard: View {
    let value: String
    let label: String
    var color: Color = Theme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).rescueFont(26, .bold).foregroundStyle(color).monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(label).rescueFont(13).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).card(radius: 18)
    }
}

struct BottomAction<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 8) { content }.padding(.horizontal, 20).padding(.top, 12).padding(
            .bottom, 12
        )
        .background {
            Theme.ivory.ignoresSafeArea(edges: .bottom)
                .shadow(color: Theme.ink.opacity(0.04), radius: 5, y: -3)
        }
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var symbol = "leaf"
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .foregroundStyle(Theme.secondary)
    }
}

struct IncomingMessageBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    var body: some View {
        if let incoming = store.incomingNotification {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.fill").foregroundStyle(Theme.save)
                    .frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                Button {
                    router.chat(incoming.senderID)
                    store.dismissIncomingNotification()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(incoming.title).rescueFont(15, .semibold)
                        Text(incoming.body).rescueFont(13).foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button {
                    store.dismissIncomingNotification()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).padding(8)
                }.buttonStyle(.plain).accessibilityLabel("Dismiss message notification")
            }.foregroundStyle(Theme.ink).padding(14).card(radius: 22)
                .shadow(color: Theme.deep.opacity(0.12), radius: 18, y: 8)
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .gesture(
                    DragGesture(minimumDistance: 15).onEnded { value in
                        if value.translation.height < -20 || abs(value.translation.width) > 35 {
                            store.dismissIncomingNotification()
                        }
                    }
                )
                .task(id: incoming.id) {
                    Haptic.success()
                    try? await Task.sleep(for: .seconds(6))
                    if !Task.isCancelled && store.incomingNotification?.id == incoming.id {
                        store.dismissIncomingNotification()
                    }
                }
        }
    }
}
