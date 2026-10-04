import SwiftUI

struct MarketplaceMapView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selectedID: String? = "straw"
    private var items: [Listing] { store.visibleListings(query: "") }
    var body: some View {
        ZStack(alignment: .bottom) {
            RescueMap(
                items: items, stops: store.runActive ? store.plan?.stops ?? [] : [],
                selectedID: $selectedID
            ).ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        router.sheet = .search
                    } label: {
                        Label("Search this area", systemImage: "magnifyingglass").rescueFont(15)
                            .frame(maxWidth: .infinity).padding(14).card(radius: 30)
                    }.buttonStyle(.plain)
                    Button {
                        router.sheet = .filters
                    } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).card(
                            radius: 22)
                    }.buttonStyle(.plain).accessibilityLabel("Filters")
                    CartButton()
                }.padding(.horizontal, 16).padding(.top, 12)
                HStack {
                    Spacer()
                    Text("\(items.count) nearby").rescueFont(13, .medium).padding(8).card(
                        radius: 20)
                }.padding(.horizontal, 16).padding(.top, 12)
                Spacer()
                if !store.runActive {
                    if items.isEmpty {
                        Text("No matches · change your filters").rescueFont(14).padding(16).card()
                            .padding(20)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(items) { item in
                                    MapListingCard(item: item, selected: selectedID == item.id) {
                                        if selectedID == item.id {
                                            router.sheet = .listing(item.id)
                                        } else {
                                            selectedID = item.id
                                        }
                                    }.id(item.id)
                                }
                            }.scrollTargetLayout().padding(.horizontal, 30)
                        }.frame(height: 126).scrollTargetBehavior(.viewAligned).scrollPosition(
                            id: $selectedID
                        )
                        .padding(.bottom, 20)
                    }
                }
            }
        }.toolbar(.hidden, for: .navigationBar).foregroundStyle(Theme.ink)
            .onChange(of: items.map(\.id)) { _, ids in
                if !ids.contains(selectedID ?? "") { selectedID = ids.first }
            }
    }
}

private struct MapListingCard: View {
    let item: Listing
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FoodPhoto(name: item.image).frame(width: 82, height: 92).clipShape(
                    RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    FreshnessBadge(freshness: item.freshness)
                    Text(item.name).rescueFont(16, .semibold).lineLimit(1)
                    Text(Money.text(item.price)).rescueFont(19, .semibold)
                    Text("~\(String(format: "%.1f", item.distance)) mi · \(item.pickup)")
                        .rescueFont(12).foregroundStyle(Theme.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(width: 264).card(radius: 22).shadow(
                color: Theme.ink.opacity(0.14), radius: 12, y: 6
            ).scaleEffect(selected ? 1 : 0.94).opacity(selected ? 1 : 0.8)
        }.buttonStyle(.plain)
    }
}
