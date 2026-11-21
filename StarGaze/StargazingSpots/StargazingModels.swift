//
//  StargazingModels.swift
//  Stargazing Spots feature
//
//  Small shared pieces used by the views:
//    - LocationProvider: real GPS, or a hardcoded test location (London, ON)
//    - SearchRadius: the 25 / 50 / 100 km picker options
//    - Bortle colours for SwiftUI (legend, badges)
//    - Driving: driving distance/time (online) + "open in Apple Maps"
//
//  Requires in the app target's Info tab:
//    "Privacy - Location When In Use Usage Description"
//    (NSLocationWhenInUseUsageDescription), e.g.
//    "Finds dark-sky stargazing spots near you."
//

import SwiftUI
import CoreLocation
import MapKit
import Observation

// MARK: - Test locations

nonisolated enum TestLocation {
    /// Downtown London, Ontario — used for indoor demos.
    static let londonON = CLLocationCoordinate2D(latitude: 42.9849, longitude: -81.2453)
    static let londonONName = "London, ON (test)"
}

// MARK: - Location

@MainActor
@Observable
final class LocationProvider {

    enum Status: Equatable {
        case idle, locating, ready, denied, failed
    }

    /// When true, the app pretends the user is in London, ON and never asks for GPS.
    var useTestLocation: Bool {
        didSet { useTestLocation ? stop() : start() }
    }

    private(set) var gpsCoordinate: CLLocationCoordinate2D?
    private(set) var status: Status = .idle

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?

    init(useTestLocation: Bool = true) {
        self.useTestLocation = useTestLocation
        if !useTestLocation { start() }
    }

    /// The coordinate the feature should search around (nil until GPS has a fix).
    var coordinate: CLLocationCoordinate2D? {
        useTestLocation ? TestLocation.londonON : gpsCoordinate
    }

    var displayName: String {
        if useTestLocation { return TestLocation.londonONName }
        switch status {
        case .ready: return "Your location"
        case .locating, .idle: return "Locating…"
        case .denied: return "Location access denied"
        case .failed: return "Location unavailable"
        }
    }

    /// Starts (or restarts) GPS. Asks for "When In Use" permission the first time.
    func start() {
        guard !useTestLocation, updatesTask == nil else { return }
        status = .locating
        session = CLServiceSession(authorization: .whenInUse)

        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        self.status = .denied
                        continue
                    }
                    guard let location = update.location else { continue }
                    // Only publish when we moved > 500 m, so spots aren't recomputed constantly.
                    if let old = self.gpsCoordinate,
                       CLLocation(latitude: old.latitude, longitude: old.longitude)
                        .distance(from: location) < 500 {
                        continue
                    }
                    self.gpsCoordinate = location.coordinate
                    self.status = .ready
                }
            } catch {
                self?.status = .failed
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        if gpsCoordinate == nil { status = .idle }
    }
}

// MARK: - Search radius

nonisolated enum SearchRadius: Int, CaseIterable, Identifiable, Sendable {
    case km25 = 25, km50 = 50, km100 = 100

    var id: Int { rawValue }
    var km: Double { Double(rawValue) }
    var label: String { "\(rawValue) km" }
}

// MARK: - Bortle colours for SwiftUI

extension Bortle {
    /// Same colours as the map overlay (see Bortle.rgb in LightPollutionService.swift).
    static func color(_ bortle: Int) -> Color {
        let c = rgb(bortle)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Short legend text, e.g. "1–2 Dark sky".
    static let legend: [(range: ClosedRange<Int>, title: String)] = [
        (1...2, "Dark sky"),
        (3...4, "Rural"),
        (5...6, "Suburban"),
        (7...9, "City"),
    ]
}

// MARK: - Driving distance + Apple Maps

nonisolated struct DriveInfo: Sendable, Equatable {
    let distanceKm: Double
    let minutes: Int
}

@MainActor
enum Driving {

    /// Driving distance and time via Apple's routing service. Needs internet;
    /// returns nil offline or if no road route exists (the UI then shows
    /// the straight-line distance only).
    static func info(from start: CLLocationCoordinate2D,
                     to spot: StargazingSpot) async -> DriveInfo? {
        let request = MKDirections.Request()
        request.source = mapItem(start, name: nil)
        request.destination = mapItem(spot.coordinate, name: nil)
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return DriveInfo(distanceKm: route.distance / 1000,
                             minutes: Int((route.expectedTravelTime / 60).rounded()))
        } catch {
            return nil
        }
    }

    /// Opens Apple Maps with driving directions to the spot.
    static func openInMaps(_ spot: StargazingSpot) {
        let item = mapItem(spot.coordinate, name: "Stargazing spot · Bortle \(spot.bortle)")
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private static func mapItem(_ c: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude),
                             address: nil)
        item.name = name
        return item
    }
}

// MARK: - Favourites (saved on the device)

@MainActor
@Observable
final class FavoriteSpotsStore {
    private(set) var spots: [StargazingSpot] = []
    private let storageKey = "stargazing.favoriteSpots.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([StargazingSpot].self, from: data) {
            spots = saved
        }
    }

    func contains(_ spot: StargazingSpot) -> Bool {
        spots.contains { $0.id == spot.id }
    }

    func toggle(_ spot: StargazingSpot) {
        if contains(spot) {
            spots.removeAll { $0.id == spot.id }
        } else {
            spots.append(spot)
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        spots.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(spots) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Formatting helpers

nonisolated enum StargazingFormat {
    static func km(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
    }

    static func minutes(_ m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func sqm(_ sqm: Double) -> String {
        String(format: "%.2f mag/arcsec²", sqm)
    }
}
