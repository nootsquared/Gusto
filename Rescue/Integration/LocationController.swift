import CoreLocation
import MapKit
import Observation

struct BrowseLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let name: String
    var shortName: String? = nil
}

/// Foreground location only. A manually chosen place takes priority over GPS callbacks.
@MainActor @Observable
final class LocationController: NSObject, @preconcurrency CLLocationManagerDelegate {
    var selection: BrowseLocation?
    var usingGPS = false
    var locating = false
    var message: String?
    var results: [MKMapItem] = []
    var searching = false
    private let preferences: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return UserDefaults(suiteName: "gusto.ui-tests.location") ?? .standard
        }
        return .standard
    }()
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var search: MKLocalSearch?
    private var lookupGeneration = UUID()
    private var fixTimeout: Task<Void, Never>?
    private let defaultsKey = "gusto.manual-browse-location"

    override init() {
        super.init()
        if let data = preferences.data(forKey: defaultsKey) {
            selection = try? JSONDecoder().decode(BrowseLocation.self, from: data)
        }
        usingGPS =
            preferences.object(forKey: "gusto.use-gps") == nil
            || preferences.bool(forKey: "gusto.use-gps")
        // Older Simulator address tests wrote this fixture into the real app preferences.
        if !preferences.bool(forKey: "gusto.location-choice-v2") {
            if selection?.name.localizedCaseInsensitiveContains("Michigan Museum of Art") == true {
                selection = nil
                preferences.removeObject(forKey: defaultsKey)
                usingGPS = true
                preferences.set(true, forKey: "gusto.use-gps")
            }
            preferences.set(true, forKey: "gusto.location-choice-v2")
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }
    var label: String {
        if usingGPS { return "Current location" }
        if let selection { return selection.shortName ?? selection.name }
        return "Choose location"
    }
    /// A country/city result is not a pickup address. The coordinate remains the destination.
    static func streetAddress(_ placemark: CLPlacemark) -> String? {
        guard let street = placemark.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines),
            !street.isEmpty else { return nil }
        let line = [placemark.subThoroughfare, street].compactMap { $0 }.joined(separator: " ")
        return [line, placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    func useCurrentLocation(refresh: Bool = false) {
        if refresh || !usingGPS {
            selection = nil
            lookupGeneration = UUID()
            geocoder.cancelGeocode()
        }
        preferences.removeObject(forKey: defaultsKey)
        usingGPS = true
        preferences.set(true, forKey: "gusto.use-gps")
        locating = selection == nil
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: startGPS()
        default:
            locating = false
            message = "Location access is off. Choose a place below or enable it in Settings."
        }
    }
    private func startGPS() {
        fixTimeout?.cancel()
        // Reuse a fresh system fix; resuming an unchanged location may emit no new callback.
        if let cached = manager.location, cached.horizontalAccuracy >= 0,
            cached.horizontalAccuracy <= 100,
            abs(cached.timestamp.timeIntervalSinceNow) < 15
        {
            locationManager(manager, didUpdateLocations: [cached])
        }
        manager.startUpdatingLocation()
        if locating {
            manager.requestLocation()
            fixTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard let self, self.usingGPS, self.locating else { return }
                self.locating = false
                self.message =
                    "Couldn't get a precise location. Enable Precise Location in Settings or search an address."
            }
        }
    }
    func requestInitially() {
        guard selection == nil, usingGPS || !preferences.bool(forKey: "gusto.location-prompted")
        else { return }
        preferences.set(true, forKey: "gusto.location-prompted")
        useCurrentLocation()
    }
    func resume() {
        if usingGPS { useCurrentLocation() }
    }
    func pause() {
        fixTimeout?.cancel()
        locating = false
        manager.stopUpdatingLocation()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard usingGPS else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: startGPS()
        case .denied, .restricted:
            locating = false
            message = "Location access is off. You can choose a place instead."
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard usingGPS, let location = locations.last, location.horizontalAccuracy >= 0,
            location.horizontalAccuracy <= 100,
            abs(location.timestamp.timeIntervalSinceNow) < 60
        else { return }
        fixTimeout?.cancel()
        locating = false
        message = nil
        if let old = selection,
            CLLocation(latitude: old.latitude, longitude: old.longitude).distance(from: location)
                < 5
        {
            return
        }
        let generation = UUID()
        lookupGeneration = generation
        selection = BrowseLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, name: "your location")
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self, self.usingGPS, self.lookupGeneration == generation else { return }
                let place = placemarks?.first
                self.selection = BrowseLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    name: place?.subLocality ?? place?.locality ?? place?.name ?? "your location")
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fixTimeout?.cancel()
        locating = false
        message = "Couldn't find your location. Try again or choose a place."
    }
    func find(_ query: String) async {
        search?.cancel()
        search = nil
        results = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            searching = false
            return
        }
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let selection {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: selection.latitude, longitude: selection.longitude),
                latitudinalMeters: 50000, longitudinalMeters: 50000)
        }
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard search === operation else { return }
            results = response.mapItems
            message =
                results.isEmpty ? "No places found. Try a city, neighborhood, or address." : nil
        } catch {
            guard search === operation else { return }
            message = "Place search is unavailable. Check your connection and try again."
        }
        if search === operation { searching = false }
    }
    func select(_ item: MKMapItem) {
        fixTimeout?.cancel()
        usingGPS = false
        preferences.set(false, forKey: "gusto.use-gps")
        manager.stopUpdatingLocation()
        geocoder.cancelGeocode()
        lookupGeneration = UUID()
        locating = false
        message = nil
        selection = BrowseLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            name: item.name ?? item.placemark.locality ?? "selected location",
            shortName: item.placemark.subLocality ?? item.placemark.locality ?? item.name)
        if let data = try? JSONEncoder().encode(selection) {
            preferences.set(data, forKey: defaultsKey)
        }
    }
}
