//
//  StargazingModels.swift
//  Stargazing Spots feature
//
//  Small shared pieces used by the views:
//    - LocationProvider: GPS, starting from the last saved location
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

// MARK: - Location

@MainActor
@Observable
final class LocationProvider {

    enum Status: Equatable {
        case idle, locating, ready, denied, failed
    }

    /// Latest GPS fix from this launch (nil until GPS answers).
    private(set) var gpsCoordinate: CLLocationCoordinate2D?
    /// Last GPS fix from a previous launch, used until GPS answers.
    private(set) var savedCoordinate: CLLocationCoordinate2D?
    private(set) var status: Status = .idle
    /// Goes up by one every time a new GPS fix is published, even if it barely moved.
    private(set) var fixCount = 0

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private static let savedLatKey = "lastKnownLatitude"
    private static let savedLonKey = "lastKnownLongitude"

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.savedLatKey) != nil {
            savedCoordinate = CLLocationCoordinate2D(latitude: defaults.double(forKey: Self.savedLatKey),
                                                     longitude: defaults.double(forKey: Self.savedLonKey))
        }
        start()
    }

    /// The coordinate the feature should search around: GPS if we have it,
    /// otherwise the last saved location (nil on the very first launch until GPS answers).
    var coordinate: CLLocationCoordinate2D? { gpsCoordinate ?? savedCoordinate }

    /// True while showing the saved location because GPS hasn't answered yet.
    var isUsingSavedLocation: Bool { gpsCoordinate == nil && savedCoordinate != nil }

    /// Re-checks the location: restarts GPS and waits (up to `timeout`) for a fresh fix.
    /// Returns true if a new fix was published, false if GPS was denied, failed or timed out.
    func refresh(timeout: Duration = .seconds(15)) async -> Bool {
        let before = fixCount
        stop()
        start(forceFirstFix: true)
        let id = UUID()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.resume(id)
        }
        await withCheckedContinuation { waiters[id] = $0 }
        timeoutTask.cancel()
        return fixCount != before
    }

    /// Starts GPS. Asks for "When In Use" permission the first time.
    /// `forceFirstFix` publishes the first fix even if it's within 500 m of the last one.
    func start(forceFirstFix: Bool = false) {
        guard updatesTask == nil else { return }
        status = .locating
        session = CLServiceSession(authorization: .whenInUse)

        updatesTask = Task { [weak self] in
            var force = forceFirstFix
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        self.status = .denied
                        self.resumeAll()
                        continue
                    }
                    guard let location = update.location else { continue }
                    // Only publish when we moved > 500 m, so spots aren't recomputed constantly.
                    if !force, let old = self.gpsCoordinate,
                       CLLocation(latitude: old.latitude, longitude: old.longitude)
                        .distance(from: location) < 500 {
                        continue
                    }
                    force = false
                    self.publish(location.coordinate)
                }
            } catch {
                self?.status = .failed
                self?.resumeAll()
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

    private func publish(_ c: CLLocationCoordinate2D) {
        gpsCoordinate = c
        status = .ready
        fixCount += 1
        UserDefaults.standard.set(c.latitude, forKey: Self.savedLatKey)
        UserDefaults.standard.set(c.longitude, forKey: Self.savedLonKey)
        resumeAll()
    }

    private func resume(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    private func resumeAll() {
        for id in Array(waiters.keys) { resume(id) }
    }
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
