import SwiftUI
import UIKit

struct LocationPickerView: View {
    @Environment(LocationController.self) private var location
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    var body: some View {
        List {
            Section {
                Button {
                    location.useCurrentLocation()
                } label: {
                    Label(location.locating ? "Finding your location…" : "Use my current location",
                          systemImage: "location.fill")
                }.accessibilityIdentifier("use-current-location")
                if let selection = location.selection {
                    Label(selection.name, systemImage: location.usingGPS ? "location" : "mappin")
                        .foregroundStyle(Theme.secondary)
                }
                if let message = location.message {
                    Text(message).font(.footnote).foregroundStyle(Theme.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            Section("Choose a city, neighborhood, or address") {
                TextField("Search places", text: $query)
                    .textInputAutocapitalization(.words).submitLabel(.search)
                    .accessibilityIdentifier("location-search")
                if location.searching { ProgressView("Searching places…") }
                ForEach(Array(location.results.enumerated()), id: \.offset) { _, item in
                    Button {
                        location.select(item)
                        router.sheet = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Location").foregroundStyle(Theme.ink)
                            Text([item.placemark.locality, item.placemark.administrativeArea,
                                  item.placemark.country].compactMap { $0 }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).background(Theme.ivory)
            .navigationTitle("Your location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.sheet = nil }
                }
            }
            .task(id: query) {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    try Task.checkCancellation()
                    await location.find(query)
                } catch { }
            }
    }
}
