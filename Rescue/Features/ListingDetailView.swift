import SwiftUI

struct ListingDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let id: String
    @State private var expanded = false
    @State private var sellerExpanded = false
    var body: some View {
        if let item = store.listing(id) {
            let seller = store.seller(item.sellerID)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FoodPhoto(name: item.image).frame(height: expanded ? 300 : 230)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 5) {
                                FreshnessBadge(freshness: item.freshness, solid: true)
                                Text("Fresh check · \(item.updated)").rescueFont(12, .semibold)
                                    .padding(6).background(Theme.paper.opacity(0.95), in: Capsule())
                            }.padding(16)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                store.toggleSaved(id)
                            } label: {
                                Image(
                                    systemName: store.savedIDs.contains(id) ? "heart.fill" : "heart"
                                ).foregroundStyle(
                                    store.savedIDs.contains(id) ? Theme.coral : Theme.ink)
                            }
                            .buttonStyle(.bordered).buttonBorderShape(.circle).tint(Theme.paper)
                            .padding(14).accessibilityLabel("Save listing")
                        }
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.name).rescueFont(26, .semibold).accessibilityIdentifier(
                            "listing-title")
                        PriceLabel(item: item, size: 34)
                        Text("You save \(Money.text(item.savings))").rescueFont(15, .medium)
                            .foregroundStyle(Theme.save)
                        Label(
                            "\(String(format: "%.1f", item.distance)) mi · \(seller.area) · \(item.pickup)",
                            systemImage: "mappin.and.ellipse"
                        ).rescueFont(14).foregroundStyle(Theme.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation(Theme.spring) { sellerExpanded.toggle() }
                            } label: {
                                HStack {
                                    SellerRow(seller: seller)
                                    Image(
                                        systemName: sellerExpanded ? "chevron.up" : "chevron.down")
                                }
                            }.buttonStyle(.plain)
                            if sellerExpanded {
                                Divider()
                                Label(
                                    seller.student
                                        ? "Identity & student verified" : "Identity verified",
                                    systemImage: "checkmark.seal.fill"
                                ).rescueFont(13).foregroundStyle(Theme.sage)
                                Button("Message \(seller.firstName)") { router.chat(seller.id) }
                                    .rescueFont(14, .semibold)
                            }
                        }.padding(12).card(radius: 18)
                        freshnessCallout(item, seller: seller)
                        Button {
                            withAnimation(Theme.spring) { expanded.toggle() }
                        } label: {
                            Label(
                                expanded ? "Hide details" : "Storage, allergens & receipt",
                                systemImage: expanded ? "chevron.up" : "chevron.down"
                            ).rescueFont(13, .medium).frame(maxWidth: .infinity).padding(
                                .vertical, 8)
                        }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                        if expanded {
                            Text("DETAILS").rescueFont(13, .semibold).foregroundStyle(Theme.muted)
                                .padding(.top, 10)
                            VStack(spacing: 0) {
                                detail("Quantity", item.quantity, "shippingbox")
                                detail(
                                    "Condition",
                                    item.opened ? "Opened, sealed storage" : "Unopened",
                                    "shippingbox")
                                detail("Storage", item.storage, "snowflake")
                                detail("Allergens", item.allergens, "exclamationmark.circle")
                                detail(
                                    item.prepared ? "Prepared" : "Purchased", item.purchased,
                                    "calendar")
                                detail(
                                    "Receipt", item.receipt ? "Verified" : "Not provided",
                                    "receipt", last: true)
                            }.padding(.horizontal, 14).card(radius: 18)
                            Text("SAFETY").rescueFont(13, .semibold).foregroundStyle(Theme.muted)
                                .padding(.top, 8)
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8
                            ) {
                                ForEach(
                                    [
                                        "Eligible for marketplace", "Seller verified",
                                        item.receipt ? "Receipt verified" : "Seller-confirmed date",
                                        "Condition reconfirmed",
                                    ], id: \.self
                                ) { text in
                                    Label(text, systemImage: "checkmark").rescueFont(12, .medium)
                                        .foregroundStyle(Theme.sage).padding(10).frame(
                                            maxWidth: .infinity, alignment: .leading
                                        ).card(radius: 14)
                                }
                            }
                            Text(
                                "Freshness is seller-reported and photo-assisted. Always use your judgment at pickup."
                            ).rescueFont(12).foregroundStyle(Theme.muted)
                            Label(
                                "Keeps \(String(format: "%.1f", item.weight)) lb of food in use. \(seller.firstName) has rescued \(seller.pickups) items.",
                                systemImage: "leaf"
                            ).rescueFont(14).padding(16).background(
                                Theme.butterSoft, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }.padding(20)
                }
            }.navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    BottomAction {
                        if !item.available {
                            PrimaryButton(title: "No longer available", disabled: true) {}
                        } else if store.cart.contains(id) {
                            HStack {
                                Label("Reserved for this demo", systemImage: "checkmark")
                                    .rescueFont(14, .semibold).foregroundStyle(Theme.deep)
                                Spacer()
                                Button("View cart") { router.sheet = .cart }.rescueFont(
                                    15, .semibold
                                ).accessibilityIdentifier("view-cart")
                            }
                        } else {
                            PrimaryButton(
                                title: "Reserve · \(Money.text(item.price))",
                                disabled: store.runActive, id: "reserve"
                            ) { if store.reserve(id) { Haptic.success() } }
                        }
                    }
                }
        } else {
            EmptyState(title: "Listing unavailable", message: "Try another item nearby.")
        }
    }
    private func freshnessCallout(_ item: Listing, seller: Seller) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: item.stale ? "exclamationmark.circle" : "checkmark.shield")
                    .foregroundStyle(item.stale ? Theme.apricot : Theme.sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        item.updated == "just now"
                            ? "Updated just now · Still good" : "Photo updated \(item.updated)"
                    ).rescueFont(14, .semibold)
                    Text(item.stale ? "Want a current look?" : "Seller reconfirmed condition")
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            if store.checkingIDs.contains(id) {
                HStack {
                    ProgressView()
                    Text("Asked \(seller.firstName) to reconfirm").rescueFont(13)
                }
            } else {
                Button {
                    Task {
                        await store.freshCheck(id)
                        Haptic.success()
                    }
                } label: {
                    Label("Request Fresh Check", systemImage: "camera").rescueFont(13, .semibold)
                }.buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier(
                    "fresh-check")
            }
        }.padding(16).background(
            item.stale ? Theme.apricotSoft : Theme.soft, in: RoundedRectangle(cornerRadius: 18))
    }
    private func detail(_ label: String, _ value: String, _ icon: String, last: Bool = false)
        -> some View
    {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(Theme.muted)
                Text(label).foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
            }.rescueFont(14).padding(.vertical, 12)
            if !last { Divider().overlay(Theme.line) }
        }
    }
}
