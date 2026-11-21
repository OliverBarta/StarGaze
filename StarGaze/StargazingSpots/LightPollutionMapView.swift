//
//  LightPollutionMapView.swift
//  Stargazing Spots feature
//
//  MKMapView wrapped for SwiftUI. SwiftUI's own `Map` can't draw a custom image
//  layer, so we use MapKit's UIKit map here. It shows:
//    - the light-pollution overlay (one image per loaded 5° tile)
//    - the cloud layer for the selected hour (translucent white squares)
//    - the search circle, the top spots (numbered pins), favourites (star pins)
//      and the test location (grey pin) or the real user location (blue dot)
//

import SwiftUI
import MapKit

// MARK: - Overlays and annotations
// These are `nonisolated` with immutable properties because MapKit reads
// overlays and draws renderers on background threads.

nonisolated final class LightTileOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let key: TileKey
    let image: CGImage
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(key: TileKey, image: CGImage) {
        self.key = key
        self.image = image
        let d = Double(TileKey.degrees)
        let south = max(-85.05, Double(key.lat0)), north = min(85.05, Double(key.lat0) + d)
        let west = Double(key.lon0), east = west + d
        coordinate = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        super.init()
    }
}

/// Draws a tile's pre-rendered colour image stretched over its 5° square.
nonisolated final class LightTileRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let tile = overlay as? LightTileOverlay else { return }
        let r = rect(for: tile.boundingMapRect)
        context.saveGState()
        // MapKit's y axis points down, Core Graphics images draw y-up: flip.
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .medium     // smooth the 1.4 km cells a little
        context.draw(tile.image, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        context.restoreGState()
    }
}

nonisolated final class SpotAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let spot: StargazingSpot
    let rank: Int?                 // nil = favourite that isn't in the current top 5
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(spot: StargazingSpot, rank: Int?) {
        self.spot = spot
        self.rank = rank
        self.coordinate = spot.coordinate
        self.title = rank.map { "Spot \($0)" } ?? "Favourite"
        super.init()
    }
}

nonisolated final class TestLocationAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D
    let title: String? = TestLocation.londonONName

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Map view

struct LightPollutionMapView: UIViewRepresentable {
    let service: LightPollutionService
    /// Pass `service.tiles.count` so SwiftUI updates the map when tiles finish loading.
    let tileCount: Int
    let centre: CLLocationCoordinate2D?
    let isTestLocation: Bool
    let radiusKm: Double
    let spots: [StargazingSpot]
    let favorites: [StargazingSpot]
    let cloudCells: [CloudCell]
    let showClouds: Bool
    let showLightPollution: Bool
    @Binding var selectedSpot: StargazingSpot?
    /// Called when the user pans/zooms: (visible centre, approx. visible radius in km).
    var onRegionChange: (CLLocationCoordinate2D, Double) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .dark      // night-friendly map
        map.showsCompass = true
        map.showsScale = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LightPollutionMapView

        private var tileOverlays: [TileKey: LightTileOverlay] = [:]
        private var cloudOverlays: [MKPolygon] = []
        private var shownCloudCells: [CloudCell] = []
        private var circle: MKCircle?
        private var circleKey = ""
        private var annotationKey = ""
        private var lastSelectedID: String?
        private var isSyncingSelection = false

        init(parent: LightPollutionMapView) { self.parent = parent }

        func sync(_ map: MKMapView) {
            map.showsUserLocation = !parent.isTestLocation
            syncTiles(map)
            syncClouds(map)
            syncCircle(map)
            syncAnnotations(map)
            syncSelection(map)
        }

        private func syncTiles(_ map: MKMapView) {
            guard parent.showLightPollution else {
                map.removeOverlays(Array(tileOverlays.values))
                tileOverlays.removeAll()
                return
            }
            for key in parent.service.tiles.keys where tileOverlays[key] == nil {
                guard let image = parent.service.overlayImage(for: key) else { continue }  // ocean
                let overlay = LightTileOverlay(key: key, image: image)
                tileOverlays[key] = overlay
                map.addOverlay(overlay, level: .aboveRoads)
            }
        }

        private func syncClouds(_ map: MKMapView) {
            let wanted = parent.showClouds ? parent.cloudCells : []
            guard wanted != shownCloudCells else { return }
            map.removeOverlays(cloudOverlays)
            cloudOverlays = wanted.map { cell in
                var corners = [
                    CLLocationCoordinate2D(latitude: cell.minLat, longitude: cell.minLon),
                    CLLocationCoordinate2D(latitude: cell.minLat, longitude: cell.maxLon),
                    CLLocationCoordinate2D(latitude: cell.maxLat, longitude: cell.maxLon),
                    CLLocationCoordinate2D(latitude: cell.maxLat, longitude: cell.minLon),
                ]
                let polygon = MKPolygon(coordinates: &corners, count: corners.count)
                polygon.title = String(cell.cover)     // read back by the renderer
                return polygon
            }
            map.addOverlays(cloudOverlays, level: .aboveLabels)
            shownCloudCells = wanted
        }

        private func syncCircle(_ map: MKMapView) {
            guard let c = parent.centre else { return }
            let key = String(format: "%.4f,%.4f,%.0f", c.latitude, c.longitude, parent.radiusKm)
            guard key != circleKey else { return }
            let firstTime = circleKey.isEmpty
            circleKey = key
            if let circle { map.removeOverlay(circle) }
            let newCircle = MKCircle(center: c, radius: parent.radiusKm * 1000)
            circle = newCircle
            map.addOverlay(newCircle, level: .aboveLabels)
            let metres = parent.radiusKm * 2_600     // circle + a margin
            map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: metres, longitudinalMeters: metres),
                          animated: !firstTime)
        }

        private func syncAnnotations(_ map: MKMapView) {
            let spotIDs = parent.spots.map(\.id)
            let extraFavorites = parent.favorites.filter { !spotIDs.contains($0.id) }
            let testCentre = parent.isTestLocation ? parent.centre : nil
            let key = spotIDs.joined(separator: "|") + "#" + extraFavorites.map(\.id).joined(separator: "|")
                + "#" + (testCentre.map { "\($0.latitude),\($0.longitude)" } ?? "")
            guard key != annotationKey else { return }
            annotationKey = key

            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            var items: [MKAnnotation] = []
            for (index, spot) in parent.spots.enumerated() {
                items.append(SpotAnnotation(spot: spot, rank: index + 1))
            }
            for spot in extraFavorites {
                items.append(SpotAnnotation(spot: spot, rank: nil))
            }
            if let testCentre { items.append(TestLocationAnnotation(coordinate: testCentre)) }
            map.addAnnotations(items)
            lastSelectedID = nil
        }

        private func syncSelection(_ map: MKMapView) {
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            guard let selected = parent.selectedSpot else {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
                lastSelectedID = nil
                return
            }
            guard selected.id != lastSelectedID else { return }
            lastSelectedID = selected.id
            if let annotation = map.annotations
                .compactMap({ $0 as? SpotAnnotation })
                .first(where: { $0.spot.id == selected.id }) {
                map.selectAnnotation(annotation, animated: true)
                if !map.visibleMapRect.contains(MKMapPoint(annotation.coordinate)) {
                    map.setCenter(annotation.coordinate, animated: true)
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? LightTileOverlay {
                let renderer = LightTileRenderer(overlay: tile)
                renderer.alpha = 0.6
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.8)
                renderer.lineWidth = 2
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let cover = Double(polygon.title ?? "") ?? 0
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.white.withAlphaComponent(min(1, cover / 100) * 0.55)
                renderer.strokeColor = nil
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let spotAnnotation = annotation as? SpotAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "spot") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: spotAnnotation, reuseIdentifier: "spot")
                view.annotation = spotAnnotation
                view.markerTintColor = UIColor(Bortle.color(spotAnnotation.spot.bortle))
                if let rank = spotAnnotation.rank {
                    view.glyphText = "\(rank)"
                    view.glyphImage = nil
                } else {
                    view.glyphText = nil
                    view.glyphImage = UIImage(systemName: "star.fill")
                }
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }

            if let test = annotation as? TestLocationAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "test") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: test, reuseIdentifier: "test")
                view.annotation = test
                view.markerTintColor = .systemGray
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard !isSyncingSelection, let spotAnnotation = annotation as? SpotAnnotation else { return }
            lastSelectedID = spotAnnotation.spot.id
            parent.selectedSpot = spotAnnotation.spot
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            guard !isSyncingSelection, annotation is SpotAnnotation else { return }
            lastSelectedID = nil
            parent.selectedSpot = nil
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let radiusKm = region.span.latitudeDelta * 111.32 / 2
            parent.onRegionChange(region.center, radiusKm)
        }
    }
}
