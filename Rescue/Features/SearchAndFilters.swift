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
            Text("\(store.selectedPill) and your filters are kept").rescueFont(12).foregroundStyle(
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
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
        }.navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
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
                HStack {
                    Text("Within")
                    Spacer()
                    Text("\(store.filters.distance, specifier: "%.1f") mi").monospacedDigit()
                }
                Slider(value: $store.filters.distance, in: 0.2...3, step: 0.1)
            }
            Section("Max price") {
                HStack {
                    Text("Price")
                    Spacer()
                    Text(Money.text(store.filters.maxPrice))
                }
                Slider(
                    value: Binding(
                        get: { Double(store.filters.maxPrice) },
                        set: { store.filters.maxPrice = Int($0) }), in: 100...1500, step: 50)
            }
            Section("Availability") {
                Toggle("Available now", isOn: $store.filters.availableNow).accessibilityIdentifier(
                    "filter-now")
                Toggle("Tonight", isOn: $store.filters.tonight).accessibilityIdentifier(
                    "filter-tonight")
                Toggle("Tomorrow", isOn: $store.filters.tomorrow).accessibilityIdentifier(
                    "filter-tomorrow")
            }
            Section("Freshness") {
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
                    ) { FreshnessBadge(freshness: value) }
                }
            }
            Section("Category") {
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
            Section("Preferences") {
                Toggle("Vegetarian", isOn: $store.filters.vegetarian)
                Toggle("Unopened", isOn: $store.filters.unopened)
                Picker("Seller rating", selection: $store.filters.minimumRating) {
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
                        store.selectedPill = "Near Me"
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
