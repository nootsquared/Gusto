import SwiftUI

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    private let suggestions = [
        "cheap breakfast", "vegetarian dinner tonight", "snacks under $4", "food near north campus",
        "unopened dairy",
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Try vegetarian dinner tonight", text: $query).rescueFont(17)
                    .accessibilityIdentifier("search-input").autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.accessibilityLabel("Clear search")
                }
            }.padding(16).card(radius: 16).padding(.horizontal, 20)
            Text("Your filters apply to search results").rescueFont(12).foregroundStyle(
                Theme.muted
            ).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(
                .top, 8)
            if query.isEmpty {
                List(suggestions, id: \.self) { suggestion in
                    Button {
                        query = suggestion
                    } label: {
                        Label(suggestion, systemImage: "clock").foregroundStyle(Theme.ink)
                    }.listRowBackground(Theme.ivory)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            } else {
                let results = store.visibleListings(query: query)
                if results.isEmpty {
                    EmptyState(
                        title: "No food found",
                        message: "Try another search or loosen your filters.",
                        symbol: "magnifyingglass")
                } else {
                    List {
                        Text("\(results.count) results nearby").rescueFont(13).foregroundStyle(
                            Theme.secondary
                        ).listRowBackground(Theme.ivory)
                        ForEach(results) { item in
                            ListingRow(item: item, identifierPrefix: "result").listRowBackground(
                                Theme.ivory)
                        }
                        if store.isBackend && !store.searchCursor.isEmpty {
                            Button("Load more results") { Task { await store.loadSearchPage() } }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
        }.task(id: query) { await store.searchBackend(query) }.navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FiltersView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    private let categories = [
        "Produce", "Dairy", "Bakery", "Pantry", "Breakfast", "Prepared", "Snacks",
    ]
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Distance") {
                HStack(spacing: 8) {
                    ForEach([0.5, 0.8, 1.5, 3.0], id: \.self) { radius in
                        let selected = store.filters.distance == radius
                        Button {
                            store.filters.distance = radius
                            Haptic.tap()
                        } label: {
                            Text(
                                "\(radius.formatted(.number.precision(.fractionLength(0...1)))) mi"
                            )
                            .rescueFont(13, .semibold).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? Theme.paper : Theme.ink)
                            .background(
                                selected ? Theme.deep : Theme.bone,
                                in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Within \(radius) miles")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("filter-distance-\(radius)")
                    }
                }.padding(.vertical, 4)
            }
            Section("Budget") {
                Picker("Maximum price", selection: $store.filters.maxPrice) {
                    Text("Up to $3").tag(300)
                    Text("Up to $5").tag(500)
                    Text("Up to $10").tag(1000)
                    Text("Up to $15").tag(1500)
                }.accessibilityIdentifier("filter-price")
            }
            Section {
                Toggle("Available now", isOn: $store.filters.availableNow).accessibilityIdentifier(
                    "filter-now")
                Toggle("Tonight", isOn: $store.filters.tonight).accessibilityIdentifier(
                    "filter-tonight")
                Toggle("Tomorrow", isOn: $store.filters.tomorrow).accessibilityIdentifier(
                    "filter-tomorrow")
            } header: {
                Text("Pickup time")
            } footer: {
                Text("Choose any times that work. Leave all off for any time.")
            }
            Section {
                ForEach(Freshness.allCases, id: \.self) { value in
                    Toggle(
                        isOn: Binding(
                            get: { store.filters.freshness.contains(value) },
                            set: {
                                if $0 {
                                    store.filters.freshness.insert(value)
                                } else {
                                    store.filters.freshness.remove(value)
                                }
                            })
                    ) { Text(value.rawValue) }
                }
            } header: {
                Text("Freshness")
            } footer: {
                Text("Choose any conditions you’re happy with. Leave all off for any condition.")
            }
            Section("Food category") {
                ForEach(categories, id: \.self) { value in
                    Toggle(
                        value,
                        isOn: Binding(
                            get: { store.filters.categories.contains(value) },
                            set: {
                                if $0 {
                                    store.filters.categories.insert(value)
                                } else {
                                    store.filters.categories.remove(value)
                                }
                            }))
                }
            }
            Section("Food preferences") {
                Toggle("Vegetarian", isOn: $store.filters.vegetarian)
                Toggle("Unopened", isOn: $store.filters.unopened)
            }
            Section("Seller") {
                Picker("Minimum rating", selection: $store.filters.minimumRating) {
                    Text("Any").tag(0.0)
                    Text("4.5+").tag(4.5)
                    Text("4.8+").tag(4.8)
                }
            }
        }.scrollContentBackground(.hidden).tint(Theme.sage).navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        store.filters = Filters()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    PrimaryButton(
                        title: "Show \(store.visibleListings(query: "").count) results",
                        id: "apply-filters"
                    ) { router.sheet = nil }
                }
            }
    }
}
