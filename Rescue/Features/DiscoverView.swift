import SwiftUI

struct CartButton: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    var body: some View {
        Button {
            router.sheet = .cart
        } label: {
            Image(systemName: "bag").frame(width: 44, height: 44).card(radius: 22)
                .overlay(alignment: .topTrailing) {
                    if !store.cart.isEmpty {
                        Text("\(store.cart.count)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(5).background(Theme.apricot, in: Circle()).offset(x: 3, y: -3)
                    }
                }
        }.buttonStyle(.plain).accessibilityLabel("Cart, \(store.cart.count) items")
            .accessibilityIdentifier("cart")
    }
}

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    private let pills = [
        "Near Me", "Under $5", "Use Soon", "Available Now", "Unopened", "Vegetarian",
    ]
    private var feed: [Listing] { store.visibleListings(query: "") }
    private var picked: [Listing] {
        let order = ["straw", "avo", "gran", "yog", "eggs"]
        return order.compactMap(store.listing).filter(store.filters.accepts)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Good evening").rescueFont(32, .bold).tracking(-0.8)
                            Label("Near Linden Park", systemImage: "mappin.and.ellipse").rescueFont(
                                15
                            ).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        CartButton()
                    }
                    HStack(spacing: 8) {
                        Button {
                            router.sheet = .search
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                Text("What are you looking for?").rescueFont(17)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.muted).padding(.horizontal, 16).frame(height: 54)
                            .card(radius: 18)
                        }.buttonStyle(.plain).accessibilityIdentifier("search")
                        Button {
                            router.sheet = .filters
                        } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 54, height: 54)
                                .card(radius: 18)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Filters")
                    }
                }.padding(.horizontal, 20).padding(.top, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pills, id: \.self) { pill in
                            Chip(title: pill, selected: store.selectedPill == pill) {
                                store.selectedPill = pill
                            }
                        }
                    }.padding(.horizontal, 20)
                }.padding(.top, 16)
                FeedSection(
                    title: "Picked for you", subtitle: "Based on what you rescue", items: picked
                ) { rail(picked) }
                FeedSection(
                    title: "Buy again",
                    items: ["straw", "bana", "yog", "gran"].compactMap(store.listing)
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(
                                ["straw", "bana", "yog", "gran"].compactMap(store.listing).filter(
                                    store.filters.accepts)
                            ) { item in
                                Button {
                                    if store.reserve(item.id) { Haptic.success() }
                                } label: {
                                    HStack(spacing: 8) {
                                        FoodPhoto(name: item.image).frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(
                                                item.name.replacingOccurrences(
                                                    of: "Organic ", with: ""
                                                ).replacingOccurrences(of: "Unopened ", with: "")
                                                    .replacingOccurrences(of: "Ripe ", with: "")
                                            ).rescueFont(13, .semibold)
                                            Text(
                                                store.cart.contains(item.id)
                                                    ? "Added ✓"
                                                    : "\(Money.text(item.price)) · \(String(format: "%.1f", item.distance)) mi"
                                            ).rescueFont(12).foregroundStyle(Theme.secondary)
                                        }
                                    }.padding(4).padding(.trailing, 10).card(
                                        radius: 30,
                                        color: store.cart.contains(item.id)
                                            ? Theme.soft : Theme.paper)
                                }.buttonStyle(.plain).disabled(
                                    store.runActive || store.cart.contains(item.id)
                                ).accessibilityIdentifier("buy-again-\(item.id)")
                            }
                        }.padding(.horizontal, 20)
                    }
                }
                FeedSection(
                    title: "Just listed near you", items: feed.sorted { $0.distance < $1.distance }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            let nearby = Array(
                                feed.filter { $0.distance <= 0.7 }.sorted {
                                    $0.distance < $1.distance
                                }.prefix(9))
                            ForEach(Array(stride(from: 0, to: nearby.count, by: 3)), id: \.self) {
                                start in
                                VStack(spacing: 0) {
                                    ForEach(Array(nearby[start..<min(start + 3, nearby.count)])) {
                                        item in
                                        ListingRow(item: item)
                                        if item.id != nearby[min(start + 2, nearby.count - 1)].id {
                                            Divider().overlay(Theme.line)
                                        }
                                    }
                                }.frame(width: 315)
                            }
                        }.padding(.horizontal, 20)
                    }
                }
                FeedSection(
                    title: "Dinner tonight", items: feed.filter { $0.category == "Prepared" }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(feed.filter { $0.category == "Prepared" }) { item in
                                MealCard(item: item)
                            }
                        }.padding(.horizontal, 20)
                    }
                }
                FeedSection(
                    title: "Grab-and-go snacks",
                    items: feed.filter {
                        $0.category == "Snacks" || ["bana", "cereal"].contains($0.id)
                    }
                ) {
                    rail(
                        feed.filter {
                            $0.category == "Snacks" || ["bana", "cereal"].contains($0.id)
                        }, width: 118)
                }
                FeedSection(title: "Ending soon", items: feed.filter { $0.freshness == .useSoon }) {
                    rail(feed.filter { $0.freshness == .useSoon }, width: 132, urgency: true)
                }
                FeedSection(
                    title: "Best deals near you", items: feed.sorted { $0.discount > $1.discount }
                ) {
                    rail(
                        Array(feed.sorted { $0.discount > $1.discount }.prefix(6)), width: 156,
                        deal: true)
                }
                Text("Better prices. Less waste. One trip.").rescueFont(13).foregroundStyle(
                    Theme.muted
                ).frame(maxWidth: .infinity).padding(.top, 40).padding(.bottom, 32)
            }
        }.background(Theme.ivory).foregroundStyle(Theme.ink).toolbar(.hidden, for: .navigationBar)
    }
    private func rail(
        _ items: [Listing], width: CGFloat = 144, urgency: Bool = false, deal: Bool = false
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    ListingTile(
                        item: item, width: width,
                        badge: urgency ? item.pickup : deal ? "−\(item.discount)%" : nil,
                        urgency: urgency)
                }
            }.padding(.horizontal, 20)
        }
    }
}

struct FeedSection<Content: View>: View {
    @Environment(AppRouter.self) private var router
    let title: String
    var subtitle: String? = nil
    let items: [Listing]
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).rescueFont(20, .semibold).tracking(-0.3)
                    if let subtitle {
                        Text(subtitle).rescueFont(13).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Button {
                    router.sheet = .collection(title, items.map(\.id))
                } label: {
                    Image(systemName: "chevron.right").rescueFont(13).frame(width: 32, height: 32)
                        .background(Theme.bone, in: Circle()).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel(
                    "See all \(title)")
            }.padding(.horizontal, 20)
            if items.isEmpty {
                Text("No matches with these filters").rescueFont(14).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 20)
            } else {
                content
            }
        }.padding(.top, 32)
    }
}

struct MealCard: View {
    @Environment(AppRouter.self) private var router
    let item: Listing
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                router.sheet = .listing(item.id)
            } label: {
                FoodPhoto(name: item.image).frame(width: 212, height: 128).clipShape(
                    RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
                .overlay(alignment: .bottomTrailing) { AddButton(item: item).padding(2) }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).rescueFont(15, .semibold).lineLimit(1)
                    Text("\(item.distance, specifier: "%.1f") mi · \(item.pickup)").rescueFont(12)
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Money.text(item.price)).rescueFont(16, .semibold)
            }
        }.frame(width: 212)
    }
}

struct CollectionView: View {
    @Environment(AppStore.self) private var store
    let title: String
    let ids: [String]
    var body: some View {
        List(ids.compactMap(store.listing)) { item in
            ListingRow(item: item).listRowBackground(Theme.ivory)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
