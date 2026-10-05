import SwiftUI

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
                            .gustoFont(13, .semibold).lineLimit(1)
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
                    Text("3 stars+").tag(3.0)
                    Text("4 stars+").tag(4.0)
                    Text("5 stars").tag(5.0)
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
