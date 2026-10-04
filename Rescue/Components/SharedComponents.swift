import SwiftUI

struct FoodPhoto: View {
    let name: String
    @State private var remoteImage: UIImage?
    var body: some View {
        GeometryReader { geometry in
            if name.hasPrefix("/") || name.hasPrefix("http") {
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
            Circle().fill(
                freshness == .fresh ? Theme.sage : freshness == .good ? Theme.butter : Theme.coral
            ).frame(width: 6, height: 6)
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
        let reserved = store.cart.contains(item.id)
        Button {
            if store.reserve(item.id) { Haptic.success() }
        } label: {
            Image(systemName: reserved ? "checkmark" : "plus").rescueFont(14, .semibold)
                .frame(width: 28, height: 28).foregroundStyle(reserved ? Theme.paper : Theme.ink)
                .background(reserved ? Theme.sage : Theme.paper, in: Circle())
                .shadow(color: Theme.ink.opacity(0.07), radius: 3, y: 2)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(reserved || store.runActive || !item.available)
            .accessibilityLabel(reserved ? "Reserved \(item.name)" : "Add \(item.name)")
            .accessibilityIdentifier("add-\(item.id)")
    }
}

struct ListingTile: View {
    @Environment(AppRouter.self) private var router
    let item: Listing
    var width: CGFloat = 144
    var badge: String? = nil
    var urgency = false
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
                    if let badge {
                        Text(badge).rescueFont(11, .semibold).foregroundStyle(Theme.paper).padding(
                            .horizontal, 7
                        ).padding(.vertical, 4).background(
                            urgency ? Theme.apricot : Theme.save, in: Capsule()
                        ).padding(8)
                    }
                }
            Text(item.name).rescueFont(14, .semibold).lineLimit(1)
            HStack(spacing: 5) {
                Text(Money.text(item.price)).rescueFont(16, .semibold)
                Text("\(item.discount)% off").rescueFont(12, .medium).foregroundStyle(Theme.save)
                Spacer(minLength: 0)
                Text("\(item.distance, specifier: "%.1f") mi").rescueFont(12).foregroundStyle(
                    Theme.muted)
            }.monospacedDigit().minimumScaleFactor(0.75)
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
                        HStack(spacing: 6) {
                            Text(Money.text(item.price)).rescueFont(15, .semibold)
                            Text("\(item.discount)% off").foregroundStyle(Theme.save)
                            Text("· \(item.distance, specifier: "%.1f") mi").foregroundStyle(
                                Theme.muted)
                        }.rescueFont(12).monospacedDigit()
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
