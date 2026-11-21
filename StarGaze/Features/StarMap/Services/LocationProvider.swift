import Foundation
import CoreLocation
import Observation

/// Gets the phone's rough location (city-level is plenty for star positions).
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    /// Used until real location arrives, or if the user says no.
    static let fallback = CLLocationCoordinate2D(latitude: 42.98, longitude: -81.25) // London, ON

    var latitude: Double = LocationProvider.fallback.latitude
    var longitude: Double = LocationProvider.fallback.longitude
    var usingFallback = true
    /// Human-readable place for collection cards, e.g. "London, Ontario".
    var placeName = "London, Ontario"

    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var didGeocode = false

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.latitude = c.latitude
            self.longitude = c.longitude
            self.usingFallback = false
            self.lookUpPlaceName(for: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }
    }

    private func lookUpPlaceName(for location: CLLocation) {
        guard !didGeocode else { return }
        didGeocode = true
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            // Prefer a named place (park, landmark), then the city
            let name = [p.areasOfInterest?.first ?? p.locality, p.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
            Task { @MainActor in
                if !name.isEmpty { self.placeName = name }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
