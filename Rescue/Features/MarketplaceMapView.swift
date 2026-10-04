import MapKit
import SwiftUI

struct MarketplaceMapView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(LocationController.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var visibleRegion = RescueMap.region
    @State private var searchedRegion: MKCoordinateRegion?
    @State private var cameraRegion = RescueMap.region
    @State private var cameraRequest = UUID()
    @State private var searchRequest = UUID()
    @State private var moved = false
    @State private var searching = false
    @State private var searchError: String?
    @State private var viewportRevision = 0
    @State private var locationExpanded = false
    @State private var addressQuery = ""
    @State private var completedAddressQuery = ""
    @State private var addressLoading = false
    @FocusState private var addressFocused: Bool

    private var items: [Listing] {
        store.catalog.filter { item in
            guard item.sellerID != store.accountID else { return false }
            var candidate = item
            // The viewport defines map distance; other marketplace filters still apply.
            candidate.distance = 0
            guard store.filters.accepts(candidate, sellers: store.sellers) else { return false }
            guard let region = searchedRegion else { return true }
            let seller = store.seller(item.sellerID)
            let latitude = item.latitude ?? seller.latitude
            let itemLongitude = item.longitude ?? seller.longitude
            let longitude = abs(
                (itemLongitude - region.center.longitude + 540)
                    .truncatingRemainder(dividingBy: 360) - 180)
            return abs(latitude - region.center.latitude) <= region.span.latitudeDelta / 2
                && longitude <= region.span.longitudeDelta / 2
        }.sorted { $0.distance < $1.distance }
    }

    var body: some View {
        ZStack {
            MarketplaceBasemap(
                items: items, sellers: store.sellers, selectedID: $selectedID,
                cameraRegion: cameraRegion, cameraRequest: cameraRequest,
                showsUser: location.usingGPS, selectedLocation: location.selection,
                reduceMotion: reduceMotion,
                onSelect: { id in
                    selectedID = id
                    router.sheet = .listing(id)
                }
            ) { region, userMoved in
                visibleRegion = region
                if userMoved {
                    viewportRevision += 1
                    withAnimation(Theme.spring) { moved = true }
                }
            }.ignoresSafeArea(edges: .top)
            if locationExpanded {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { closeLocationMenu() }
            }
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(Theme.spring) { locationExpanded.toggle() }
                        if !locationExpanded { addressFocused = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill").foregroundStyle(Theme.save)
                            Text(location.label)
                                .rescueFont(15, .semibold).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: locationExpanded ? "chevron.up" : "chevron.down")
                                .font(
                                    .system(size: 11, weight: .semibold))
                        }.padding(15).background(Theme.paper, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("map-location")
                    Button {
                        router.sheet = .filters
                    } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
                            .background(Theme.paper, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Filters")
                    CartButton()
                }.shadow(color: Theme.ink.opacity(0.08), radius: 12, y: 4)
                if locationExpanded {
                    locationMenu.transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !locationExpanded {
                    HStack {
                        if moved || searching {
                            Button {
                                Task { await searchArea() }
                            } label: {
                                HStack(spacing: 8) {
                                    if searching {
                                        ProgressView().tint(Theme.paper)
                                    } else {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    Text(searching ? "Finding food…" : "Search this area")
                                        .rescueFont(14, .semibold)
                                }.padding(.horizontal, 18).padding(.vertical, 12)
                                    .foregroundStyle(Theme.paper).background(
                                        Theme.deep, in: Capsule())
                            }.buttonStyle(.plain).disabled(searching)
                                .accessibilityIdentifier("search-map-area")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer()
                        Button {
                            if let selection = location.selection {
                                recenter(selection)
                            } else {
                                location.useCurrentLocation()
                            }
                        } label: {
                            Image(systemName: "location.north.fill").foregroundStyle(Theme.save)
                                .frame(width: 44, height: 44).background(Theme.paper, in: Circle())
                                .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
                        }.buttonStyle(.plain).accessibilityLabel("Recenter map")
                            .accessibilityIdentifier("recenter-map")
                    }
                    Spacer()
                    if let searchError {
                        Text(searchError).rescueFont(13).padding(12)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if items.isEmpty {
                        VStack(spacing: 5) {
                            Text("No food in this area yet").rescueFont(16, .semibold)
                            Text("Try a wider area or adjust your filters.")
                                .rescueFont(13).foregroundStyle(Theme.secondary)
                            Button("Widen map area") {
                                let target = MKCoordinateRegion(
                                    center: visibleRegion.center,
                                    span: MKCoordinateSpan(
                                        latitudeDelta: min(
                                            180, visibleRegion.span.latitudeDelta * 2),
                                        longitudeDelta: min(
                                            360, visibleRegion.span.longitudeDelta * 2)))
                                cameraRegion = target
                                cameraRequest = UUID()
                                Task { await searchArea(region: target) }
                            }.rescueFont(14, .semibold).foregroundStyle(Theme.save)
                                .padding(.top, 8).accessibilityIdentifier("expand-map-area")
                        }.frame(maxWidth: .infinity).padding(20).card(radius: 24)
                    } else {
                        HStack {
                            Text("\(items.count) finds in this area").rescueFont(12, .semibold)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.paper.opacity(0.95), in: Capsule())
                            Spacer()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(items) { item in
                                    MapListingCard(item: item, selected: selectedID == item.id) {
                                        router.sheet = .listing(item.id)
                                    }.id(item.id)
                                }
                            }.scrollTargetLayout().padding(.horizontal, 16)
                        }.contentMargins(.horizontal, 0)
                            .scrollTargetBehavior(.viewAligned).scrollPosition(id: $selectedID)
                            .frame(height: 134).padding(.horizontal, -16)
                            .animation(Theme.spring, value: selectedID)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 38)
        }.toolbar(.hidden, for: .navigationBar).foregroundStyle(Theme.ink)
            .task {
                if store.online { await searchArea() }
            }
            .onChange(of: store.online) { _, online in
                if online && !searching { Task { await searchArea(region: searchedRegion ?? visibleRegion) } }
            }
            .task(id: "\(locationExpanded)-\(addressQuery)") {
                guard locationExpanded else { return }
                let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                completedAddressQuery = ""
                addressLoading = !query.isEmpty
                if query.isEmpty {
                    await location.find("")
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    await location.find(query)
                    guard !Task.isCancelled, locationExpanded,
                        addressQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
                    else { return }
                    completedAddressQuery = query
                    addressLoading = false
                } catch {}
            }
            .onChange(of: location.selection, initial: true) { _, selection in
                if let selection { recenter(selection) }
            }
            .onChange(of: store.filters) { _, _ in Task { await searchArea() } }
            .onChange(of: items.map(\.id), initial: true) { _, ids in
                if !ids.contains(selectedID ?? "") { selectedID = ids.first }
            }
    }

    private var locationMenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                addressFocused = false
                location.useCurrentLocation()
                if location.message == nil { closeLocationMenu() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill").foregroundStyle(Theme.save)
                        .frame(width: 34, height: 34).background(Theme.soft, in: Circle())
                    Text(location.locating ? "Finding your location…" : "Use current location")
                        .rescueFont(15, .semibold)
                    Spacer()
                    if location.locating { ProgressView().tint(Theme.save) }
                }.foregroundStyle(Theme.ink)
            }.buttonStyle(.plain).accessibilityIdentifier("map-use-current-location")
            Divider().overlay(Theme.line)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.save)
                TextField("Enter an address or place", text: $addressQuery)
                    .rescueFont(15).autocorrectionDisabled().textInputAutocapitalization(.words)
                    .focused($addressFocused).submitLabel(.search)
                    .accessibilityIdentifier("map-address-search")
                if !addressQuery.isEmpty {
                    Button {
                        addressQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }.buttonStyle(.plain).accessibilityLabel("Clear address")
                }
            }.padding(13).background(Theme.ivory, in: RoundedRectangle(cornerRadius: 14))
            if addressLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.save)
                    Text("Finding addresses…").rescueFont(13).foregroundStyle(Theme.secondary)
                }.padding(.vertical, 6)
            } else if !completedAddressQuery.isEmpty {
                if location.results.isEmpty {
                    Text(location.message ?? "No matching addresses. Try a city or street name.")
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(location.results.prefix(8).enumerated()), id: \.offset) {
                                index, item in
                                Button {
                                    location.select(item)
                                    closeLocationMenu()
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "mappin").foregroundStyle(Theme.save)
                                            .frame(width: 20).padding(.top, 3)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name ?? "Address").rescueFont(14, .semibold)
                                            Text(
                                                [
                                                    item.placemark.thoroughfare,
                                                    item.placemark.locality,
                                                    item.placemark.administrativeArea,
                                                ].compactMap { $0 }
                                                    .joined(separator: ", ")
                                            )
                                            .rescueFont(12).foregroundStyle(Theme.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.foregroundStyle(Theme.ink).padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier(
                                    "map-address-result-\(index)")
                                if index < min(location.results.count, 8) - 1 { Divider() }
                            }
                        }
                    }.frame(height: min(CGFloat(location.results.count) * 72, 180))
                        .scrollDismissesKeyboard(.interactively)
                }
            } else if let message = location.message {
                Text(message).rescueFont(13).foregroundStyle(Theme.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }.rescueFont(13, .semibold).foregroundStyle(Theme.save)
            }
        }.padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.12), radius: 18, y: 8)
            .accessibilityElement(children: .contain)
    }

    private func closeLocationMenu() {
        addressFocused = false
        withAnimation(Theme.spring) { locationExpanded = false }
    }

    private func recenter(_ selection: BrowseLocation) {
        cameraRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: selection.latitude, longitude: selection.longitude),
            latitudinalMeters: max(3000, store.filters.distance * 3218.688),
            longitudinalMeters: max(3000, store.filters.distance * 3218.688))
        cameraRequest = UUID()
        searchedRegion = cameraRegion
        moved = false
        Task { await searchArea(region: cameraRegion) }
    }

    private func searchArea(region: MKCoordinateRegion? = nil) async {
        let target = region ?? visibleRegion
        let request = UUID()
        let revision = viewportRevision
        searchRequest = request
        searching = true
        searchError = nil
        do {
            if store.isBackend {
                let corner = CLLocation(
                    latitude: target.center.latitude + target.span.latitudeDelta / 2,
                    longitude: target.center.longitude + target.span.longitudeDelta / 2)
                let center = CLLocation(
                    latitude: target.center.latitude, longitude: target.center.longitude)
                try await store.loadMapArea(
                    latitude: target.center.latitude,
                    longitude: target.center.longitude,
                    radiusMiles: max(0.1, center.distance(from: corner) / 1609.344))
            }
            guard searchRequest == request else { return }
            withAnimation(Theme.spring) {
                searchedRegion = target
                moved = viewportRevision != revision
            }
        } catch {
            guard searchRequest == request else { return }
            searchError = "Couldn't refresh this area. Check your connection and try again."
        }
        if searchRequest == request { searching = false }
    }
}

private struct MapListingCard: View {
    let item: Listing
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FoodPhoto(name: item.image).frame(width: 90, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.name).rescueFont(15, .semibold).lineLimit(2)
                    ListingOffer(item: item, priceSize: 18)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.save)
            }.padding(12).frame(width: 310).background(
                Theme.paper, in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24).stroke(
                    selected ? Theme.save.opacity(0.35) : Theme.line, lineWidth: 1)
            )
            .shadow(color: Theme.ink.opacity(0.1), radius: 10, y: 4)
        }.buttonStyle(MapCardPressStyle()).accessibilityIdentifier("map-listing-\(item.id)")
    }
}

private struct MapCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

private final class SellerMapAnnotation: NSObject, MKAnnotation {
    let sellerID: String
    let listings: [Listing]
    let coordinate: CLLocationCoordinate2D
    var title: String? { "\(listings.count) listings · from \(Money.text(listings[0].price))" }
    init(seller: Seller, listings: [Listing]) {
        sellerID = seller.id
        self.listings = listings.sorted { $0.price < $1.price }
        coordinate = CLLocationCoordinate2D(latitude: listings[0].latitude ?? seller.latitude,
            longitude: listings[0].longitude ?? seller.longitude)
    }
}

private final class BrowseMapAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String? = "Your selected location"
    init(_ location: BrowseLocation) {
        coordinate = CLLocationCoordinate2D(
            latitude: location.latitude, longitude: location.longitude)
        title = location.name
    }
}

private final class MarketplaceMapCanvas: MKMapView {
    override func layoutSubviews() {
        super.layoutSubviews()
        // Reserve the bottom edge for Apple's attribution, below the listing carousel.
        let margins = UIEdgeInsets(
            top: 12, left: 16,
            bottom: 8, right: 12)
        if layoutMargins != margins { layoutMargins = margins }
    }
}

private struct MarketplaceBasemap: UIViewRepresentable {
    let items: [Listing]
    let sellers: [Seller]
    @Binding var selectedID: String?
    let cameraRegion: MKCoordinateRegion
    let cameraRequest: UUID
    let showsUser: Bool
    let selectedLocation: BrowseLocation?
    let reduceMotion: Bool
    let onSelect: (String) -> Void
    let regionChanged: (MKCoordinateRegion, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MarketplaceMapCanvas()
        map.tintColor = .systemBlue
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.isPitchEnabled = false
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "seller")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "cluster")
        map.setRegion(cameraRegion, animated: false)
        map.accessibilityIdentifier = "marketplace-map"
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        map.showsUserLocation = showsUser
        let cameraChanged = coordinator.cameraRequest != cameraRequest
        if cameraChanged {
            coordinator.cameraRequest = cameraRequest
            map.setRegion(cameraRegion, animated: !reduceMotion)
        }
        let signature =
            items.map { "\($0.id):\($0.price):\($0.sellerID):\($0.latitude ?? 0):\($0.longitude ?? 0)" }.joined(separator: "|")
            + sellers.map { "\($0.id):\($0.latitude):\($0.longitude)" }.joined(separator: "|")
        if signature != coordinator.signature {
            coordinator.signature = signature
            map.removeAnnotations(
                map.annotations.filter {
                    $0 is SellerMapAnnotation || $0 is MKClusterAnnotation
                })
            let groups = Dictionary(grouping: items) { item in
                "\(item.sellerID):\(item.windows?.first?.locationID ?? item.sellerID)"
            }
            map.addAnnotations(
                groups.values.compactMap { listings in
                    guard let first = listings.first, let seller = sellers.first(where: { $0.id == first.sellerID }) else { return nil }
                    return SellerMapAnnotation(seller: seller, listings: listings)
                })
        }
        let chosenLocation = showsUser ? nil : selectedLocation
        if coordinator.browseLocation != chosenLocation {
            coordinator.browseLocation = chosenLocation
            map.removeAnnotations(map.annotations.filter { $0 is BrowseMapAnnotation })
            if let chosenLocation { map.addAnnotation(BrowseMapAnnotation(chosenLocation)) }
        }
        for annotation in map.annotations.compactMap({ $0 as? SellerMapAnnotation }) {
            if let view = map.view(for: annotation) {
                coordinator.style(view, annotation: annotation)
            }
        }
        coordinator.selectedID = selectedID
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MarketplaceBasemap
        var cameraRequest: UUID?
        var selectedID: String?
        var signature = ""
        var browseLocation: BrowseLocation?
        var userMoved = false
        init(_ parent: MarketplaceBasemap) { self.parent = parent }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            userMoved =
                mapView.subviews.first?.gestureRecognizers?.contains {
                    $0.state == .began || $0.state == .changed
                } ?? false
        }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            func isInteracting(_ view: UIView) -> Bool {
                if view.gestureRecognizers?.contains(where: {
                    $0.state == .began || $0.state == .changed
                }) == true {
                    return true
                }
                return view.subviews.contains(where: isInteracting)
            }
            if isInteracting(mapView) { userMoved = true }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Layout margins move MapKit's camera region; search the entire visible canvas.
            let region = mapView.convert(mapView.bounds, toRegionFrom: mapView)
            let moved = userMoved
            DispatchQueue.main.async { self.parent.regionChanged(region, moved) }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is BrowseMapAnnotation {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
                view.markerTintColor = UIColor(named: "Save")
                view.glyphImage = UIImage(systemName: "mappin")
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                view.canShowCallout = true
                view.accessibilityIdentifier = "selected-location-pin"
                view.accessibilityLabel = "Selected location, \(annotation.title ?? "")"
                return view
            }
            let clustered = annotation is MKClusterAnnotation
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: clustered ? "cluster" : "seller", for: annotation)
            view.clusteringIdentifier = clustered ? nil : "food-sellers"
            view.collisionMode = .rectangle
            view.displayPriority = .defaultHigh
            style(view, annotation: annotation)
            return view
        }
        func style(_ view: MKAnnotationView, annotation: MKAnnotation) {
            let selected: Bool
            let text: String
            if let seller = annotation as? SellerMapAnnotation {
                selected = seller.listings.contains { $0.id == parent.selectedID }
                // Keep the selected seller visible instead of hiding it inside a cluster.
                view.clusteringIdentifier = selected ? nil : "food-sellers"
                let item =
                    seller.listings.first { $0.id == parent.selectedID } ?? seller.listings[0]
                text =
                    (seller.listings.count > 1 && !selected ? "From " : "") + Money.text(item.price)
                view.accessibilityLabel =
                    "\(seller.listings.count) listings, from \(Money.text(seller.listings[0].price))"
            } else if let cluster = annotation as? MKClusterAnnotation {
                selected = false
                text = "\(cluster.memberAnnotations.count) places"
                view.accessibilityLabel =
                    "\(cluster.memberAnnotations.count) seller locations. Tap to zoom."
            } else {
                return
            }
            let label = UILabel()
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.text = text
            label.textColor = UIColor(named: selected ? "Paper" : "Ink")
            label.sizeToFit()
            let size = CGSize(width: label.bounds.width + 24, height: 36)
            view.image = UIGraphicsImageRenderer(size: size).image { _ in
                (UIColor(named: selected ? "SageDeep" : "Paper") ?? .white).setFill()
                UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1),
                    cornerRadius: 17
                ).fill()
                label.drawText(
                    in: CGRect(
                        x: 12, y: (36 - label.bounds.height) / 2,
                        width: label.bounds.width, height: label.bounds.height))
            }.withRenderingMode(.alwaysOriginal)
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.14
            view.layer.shadowRadius = 5
            view.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.displayPriority = selected ? .required : .defaultHigh
            view.zPriority = selected ? .max : .defaultUnselected
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { rect, annotation in
                    let point = MKMapPoint(annotation.coordinate)
                    return rect.union(
                        MKMapRect(
                            x: point.x - 250, y: point.y - 250,
                            width: 500, height: 500))
                }
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(
                        top: 130, left: 24,
                        bottom: 190, right: 24),
                    animated: !parent.reduceMotion)
                userMoved = true
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let seller = view.annotation as? SellerMapAnnotation {
                let item = seller.listings.first { $0.id == parent.selectedID } ?? seller.listings[0]
                DispatchQueue.main.async {
                    withAnimation(Theme.spring) { self.parent.onSelect(item.id) }
                    mapView.deselectAnnotation(seller, animated: false)
                    Haptic.tap()
                }
            }
        }
    }
}
