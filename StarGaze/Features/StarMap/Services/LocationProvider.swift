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
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
