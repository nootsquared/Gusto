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
    @State private var searchText = ""
    @State private var searchLoading = false
    @State private var completedSearch = ""
    @State private var searchRequest = UUID()
    @FocusState private var searchFocused: Bool
    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchActive: Bool { searchFocused || !trimmedSearch.isEmpty }
    private var searchResults: [Listing] {
        if store.isBackend && completedSearch != trimmedSearch { return [] }
        return store.visibleListings(query: trimmedSearch)
    }
    private struct SearchContext: Equatable {
        let query: String
        let filters: Filters
    }
    private var feed: [Listing] { store.visibleListings(query: "") }
    private var picked: [Listing] {
        return store.personalizedListings.filter {
            store.filters.accepts($0, sellers: store.sellers)
        }
    }
    private var firstName: String? {
        let name = store.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
            !["Sign in to Gusto", "Sign in to Rescue", "Rescue member", "Gusto member"].contains(
                name)
        else { return nil }
        return name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }
    private func greeting(at date: Date) -> String {
        switch Calendar.autoupdatingCurrent.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
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
                    HStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.save).frame(width: 32, height: 32)
                                .background(Theme.soft, in: Circle())
                            TextField("Search food nearby", text: $searchText)
                                .rescueFont(16).focused($searchFocused)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .submitLabel(.search).onSubmit { searchFocused = false }
                                .accessibilityIdentifier("search-input")
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17)).foregroundStyle(Theme.muted)
                                        .frame(width: 28, height: 36)
                                }.buttonStyle(.plain).accessibilityLabel("Clear search")
                            }
                        }.padding(.horizontal, 12).frame(height: 58)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        searchActive ? Theme.save.opacity(0.5) : Theme.line,
                                        lineWidth: 1)
                            )
                            .shadow(
                                color: Theme.deep.opacity(searchActive ? 0.07 : 0.03), radius: 12,
                                y: 4)
                        Button {
                            router.sheet = .filters
                        } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 52, height: 58)
                                .card(radius: 20)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Filters")
                    }
                }.padding(.horizontal, 20).padding(.top, 12)
                if searchActive {
                    searchContent
                } else if store.isBackend && store.catalog.isEmpty {
                    EmptyState(
                        title: store.online ? "No listings yet" : "Unable to load listings",
                        message: store.online
                            ? "Food shared by sellers will appear here. Be the first to list something."
                            : "Check your connection, then pull down to try again.")
                    if store.online {
                        PrimaryButton(title: "List food", id: "empty-feed-sell") {
                            router.tab = .sell
                        }.padding(.horizontal, 20)
                    }
                } else {
                    FeedSection(
                        title: "Picked for you", subtitle: "Based on what you like", items: picked
                    ) { rail(picked) }
                    FeedSection(
                        title: "Buy again",
                        items: store.buyAgainListings.filter {
                            store.filters.accepts($0, sellers: store.sellers)
                        }
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(
                                    store.buyAgainListings.filter {
                                        store.filters.accepts($0, sellers: store.sellers)
                                    }
                                ) { item in
                                    Button {
                                        if store.addToCart(item.id) { Haptic.success() }
                                    } label: {
                                        HStack(spacing: 12) {
                                            FoodPhoto(name: item.image).frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(
                                                    item.name.replacingOccurrences(
                                                        of: "Organic ", with: ""
                                                    ).replacingOccurrences(
                                                        of: "Unopened ", with: ""
                                                    )
                                                    .replacingOccurrences(of: "Ripe ", with: "")
                                                ).rescueFont(16, .semibold).lineLimit(1)
                                                if store.cart.contains(item.id) {
                                                    Label("In cart", systemImage: "checkmark")
                                                        .rescueFont(14, .medium).foregroundStyle(
                                                            Theme.save)
                                                } else {
                                                    HStack(spacing: 8) {
                                                        Text(Money.text(item.price)).rescueFont(
                                                            15, .bold
                                                        )
                                                        .foregroundStyle(Theme.ink)
                                                        Text(
                                                            "\(item.distance, specifier: "%.1f") mi"
                                                        )
                                                        .rescueFont(13, .medium)
                                                        .foregroundStyle(Theme.secondary)
                                                    }.lineLimit(1).monospacedDigit()
                                                }
                                            }
                                        }.frame(width: 228, alignment: .leading).padding(10).card(
                                            radius: 16,
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
                        title: "Just listed near you",
                        items: feed.sorted { $0.distance < $1.distance }
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 24) {
                                let nearby = Array(
                                    feed.filter { $0.distance <= 0.7 }.sorted {
                                        $0.distance < $1.distance
                                    }.prefix(9))
                                ForEach(Array(stride(from: 0, to: nearby.count, by: 3)), id: \.self)
                                {
                                    start in
                                    VStack(spacing: 0) {
                                        ForEach(Array(nearby[start..<min(start + 3, nearby.count)]))
                                        {
                                            item in
                                            ListingRow(item: item)
                                            if item.id
                                                != nearby[min(start + 2, nearby.count - 1)].id
                                            {
                                                Divider().overlay(Theme.line)
                                            }
                                        }
                                    }.frame(width: 315)
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
                            }, width: 164)
                    }
                    FeedSection(
                        title: "Best deals near you",
                        items: feed.sorted { $0.discount > $1.discount }
                    ) {
                        rail(
                            Array(feed.sorted { $0.discount > $1.discount }.prefix(6)), width: 164,
                            deal: true)
                    }
                }
                if !searchActive && store.isBackend && !store.feedCursor.isEmpty {
                    Color.clear.frame(height: 1)
                        .task(id: store.feedCursor) { await store.loadNextPage() }
                        .accessibilityHidden(true)
                }
            }.padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively)
            .animation(Theme.spring, value: searchActive)
            .task(
                id: SearchContext(
                    query: trimmedSearch, filters: store.filters)
            ) {
                let request = UUID()
                searchRequest = request
                guard !trimmedSearch.isEmpty else {
                    searchLoading = false
                    completedSearch = ""
                    return
                }
                let query = trimmedSearch
                searchLoading = store.isBackend
                await store.searchBackend(query)
                guard !Task.isCancelled, searchRequest == request else { return }
                completedSearch = query
                searchLoading = false
            }.refreshable {
                if !trimmedSearch.isEmpty {
                    await store.searchBackend(trimmedSearch)
                } else {
                    await store.refreshBackend(force: true)
                    await store.loadNextPage(first: true)
                }
            }.background(Theme.ivory).foregroundStyle(Theme.ink).toolbar(
                .hidden, for: .navigationBar)
    }
    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(
                    trimmedSearch.isEmpty
                        ? "Browse by category"
                        : searchLoading ? "Searching…" : "\(searchResults.count) nearby"
                )
                .rescueFont(20, .semibold)
                Spacer()
                Button("Cancel") {
                    searchFocused = false
                    searchText = ""
                }.rescueFont(14, .semibold).foregroundStyle(Theme.save)
                    .accessibilityIdentifier("cancel-search")
            }
            if trimmedSearch.isEmpty {
                let categories = Array(Set(feed.map(\.category))).sorted()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            searchText = category
                        } label: {
                            HStack {
                                Text(category).rescueFont(15, .semibold)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .medium))
                            }.foregroundStyle(Theme.deep).padding(16)
                                .background(
                                    Theme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 18)
                                )
                        }.buttonStyle(.plain)
                    }
                }
            } else if searchLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.save)
                    Text("Looking for matches nearby").rescueFont(14).foregroundStyle(
                        Theme.secondary)
                }.padding(.vertical, 24)
            } else if searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.save).padding(.bottom, 6)
                    Text(
                        store.isBackend && !store.online
                            ? "Couldn't load results" : "No matches nearby"
                    )
                    .rescueFont(22, .semibold)
                    Text(
                        store.isBackend && !store.online
                            ? "Check your connection and try again."
                            : "Try a different food or widen your filters."
                    )
                    .rescueFont(15).foregroundStyle(Theme.secondary)
                    Button("Adjust filters") { router.sheet = .filters }
                        .rescueFont(14, .semibold).foregroundStyle(Theme.save).padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).card(radius: 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(searchResults) { item in
                        DiscoverSearchCard(item: item)
                    }
                    if store.isBackend && !store.searchCursor.isEmpty {
                        ProgressView().tint(Theme.save).padding(12)
                            .task(id: store.searchCursor) { await store.loadSearchPage() }
                    }
                }.accessibilityIdentifier("search-results")
            }
        }.padding(.horizontal, 20).padding(.top, 28)
    }

    private func rail(
        _ items: [Listing], width: CGFloat = 164, deal: Bool = false
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(items) { item in
                    ListingTile(
                        item: item, width: width,
                        isDeal: deal)
                }
            }.padding(.horizontal, 20)
        }
    }
}

private struct DiscoverSearchCard: View {
    @Environment(AppRouter.self) private var router
    let item: Listing
    var body: some View {
        HStack(spacing: 12) {
            Button {
                router.sheet = .listing(item.id)
            } label: {
                HStack(spacing: 14) {
                    FoodPhoto(name: item.image).frame(width: 76, height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.name).rescueFont(16, .semibold).lineLimit(2)
                        ListingOffer(item: item, priceSize: 18)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(Theme.ink).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("result-\(item.id)")
            AddButton(item: item)
        }.padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22).stroke(Theme.line.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Theme.deep.opacity(0.035), radius: 10, y: 4)
    }
}

struct FeedSection<Content: View>: View {
    @Environment(AppRouter.self) private var router
    let title: String
    var subtitle: String? = nil
    let items: [Listing]
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).rescueFont(22, .bold).tracking(-0.3)
                    if let subtitle {
                        Text(subtitle).rescueFont(14, .medium).foregroundStyle(Theme.secondary)
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
        }.padding(.top, 24)
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
