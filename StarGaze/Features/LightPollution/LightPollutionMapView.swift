//
//  LightPollutionMapView.swift
//  Stargazing Spots feature
//
//  MKMapView wrapped for SwiftUI. SwiftUI's own `Map` can't draw a custom image
//  layer, so we use MapKit's UIKit map here. It shows:
//    - the cloud layer for the selected hour (one smooth, soft-edged white image)
//    - the heatmap of `light_readings` from Supabase (see LightReadingsHeatmap.swift)
//    - the search circle and the top spots (numbered pins)
//      and the user's location (blue dot), or a grey pin at the last known
//      location until GPS answers
//

import SwiftUI
import MapKit

// MARK: - Overlays and annotations
// These are `nonisolated` with immutable properties because MapKit reads
// overlays and draws renderers on background threads.

/// The cloud layer: the forecast grid for one hour, upscaled into a smooth image.
nonisolated final class CloudFieldOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let image: CGImage
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(field: CloudField, image: CGImage) {
        self.image = image
        // the image reaches past the forecast area by the fade margin
        let padLat = CloudImage.fadeSteps * (field.north - field.south) / Double(field.rows)
        let padLon = CloudImage.fadeSteps * (field.east - field.west) / Double(field.cols)
        let south = field.south - padLat, north = field.north + padLat
        let west = field.west - padLon, east = field.east + padLon
        coordinate = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y, width: se.x - nw.x, height: se.y - nw.y)
        super.init()
    }
}

nonisolated final class CloudFieldRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let clouds = overlay as? CloudFieldOverlay else { return }
        let r = rect(for: clouds.boundingMapRect)
        context.saveGState()
        // MapKit's y axis points down, Core Graphics images draw y-up: flip.
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(clouds.image, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        context.restoreGState()
    }
}

/// Turns the coarse forecast grid into a smooth image, without asking the API for more points:
///   - bicubic (Catmull-Rom) interpolation between grid points gives rounded, blended blobs
///     instead of squares
///   - the forecast area is drawn at full strength out to its outer edge, then fades out
///     beyond it; the fade follows the distance from that edge, so its corners are rounded
nonisolated enum CloudImage {
    /// Image pixels per forecast grid step (9 points -> 288 px, plus the fade margin).
    static let pixelsPerStep = 32
    /// Opacity at 100% cloud.
    static let maxAlpha = 0.55
    /// How far past the forecast area's outer edge the fade reaches, in grid steps.
    /// A whole number of pixels, so the overlay's bounds and the image line up exactly.
    static let fadeSteps = Double(fadePixels) / Double(pixelsPerStep)
    private static let fadePixels = 48

    static func make(_ field: CloudField) -> CGImage? {
        let dataW = field.cols * pixelsPerStep, dataH = field.rows * pixelsPerStep
        let w = dataW + 2 * fadePixels, h = dataH + 2 * fadePixels
        guard dataW > 0, dataH > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let step = Double(pixelsPerStep)

        for y in 0..<h {
            // pixel centre relative to the forecast area (0...dataH, measured from the north edge)
            let py = Double(y - fadePixels) + 0.5
            // image row 0 is north; grid row 0 is south. Grid points sit at cell centres.
            let gy = (Double(dataH) - py) / step - 0.5
            let outY = max(0, -py, py - Double(dataH))
            for x in 0..<w {
                let px = Double(x - fadePixels) + 0.5
                let gx = px / step - 0.5
                let outX = max(0, -px, px - Double(dataW))
                // 0 inside the forecast area, then the distance past its edge
                let outside = (outX * outX + outY * outY).squareRoot()
                let edge = 1 - smoothstep(0, Double(fadePixels), outside)
                guard edge > 0 else { continue }
                let cover = min(100, max(0, bicubic(field, gx, gy)))
                let alpha = UInt8((cover / 100 * maxAlpha * edge * 255).rounded())
                let i = (y * w + x) * 4
                // premultiplied white: colour channels equal alpha
                pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = alpha
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Catmull-Rom interpolation at grid position (gx, gy); points past the edge repeat the edge.
    private static func bicubic(_ f: CloudField, _ gx: Double, _ gy: Double) -> Double {
        let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
        let tx = gx - Double(x0), ty = gy - Double(y0)
        func value(_ col: Int, _ row: Int) -> Double {
            f.cover[min(f.rows - 1, max(0, row)) * f.cols + min(f.cols - 1, max(0, col))]
        }
        func cubic(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
            p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)))
        }
        var rows = [Double](repeating: 0, count: 4)
        for k in 0..<4 {
            let row = y0 - 1 + k
            rows[k] = cubic(value(x0 - 1, row), value(x0, row), value(x0 + 1, row), value(x0 + 2, row), tx)
        }
        return cubic(rows[0], rows[1], rows[2], rows[3], ty)
    }
}

nonisolated final class SpotAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let spot: StargazingSpot
    let rank: Int
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(spot: StargazingSpot, rank: Int) {
        self.spot = spot
        self.rank = rank
        self.coordinate = spot.coordinate
        self.title = "Spot \(rank)"
        super.init()
    }
}

nonisolated final class SavedLocationAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D
    let title: String? = "Last known location"

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Map view

struct LightPollutionMapView: UIViewRepresentable {
    let centre: CLLocationCoordinate2D?
    /// True while `centre` is the saved location from a previous launch, not live GPS.
    let isSavedLocation: Bool
    let radiusKm: Double
    let spots: [StargazingSpot]
    let cloudField: CloudField?
    let showClouds: Bool
    var lightReadings: [LightReading] = []
    var showHeatmap = false
    @Binding var selectedSpot: StargazingSpot?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .dark      // night-friendly map
        map.showsCompass = true
        map.showsScale = true
        map.showsUserLocation = true
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

        private var cloudOverlay: CloudFieldOverlay?
        private var shownCloudField: CloudField?
        private var heatmapOverlay: LightReadingsOverlay?
        private var circle: MKCircle?
        private var circleKey = ""
        private var annotationKey = ""
        private var lastSelectedID: String?
        private var isSyncingSelection = false

        init(parent: LightPollutionMapView) { self.parent = parent }

        func sync(_ map: MKMapView) {
            syncClouds(map)
            syncHeatmap(map)
            syncCircle(map)
            syncAnnotations(map)
            syncSelection(map)
        }

        private func syncClouds(_ map: MKMapView) {
            let wanted = parent.showClouds ? parent.cloudField : nil
            guard wanted != shownCloudField else { return }
            shownCloudField = wanted
            let old = cloudOverlay
            cloudOverlay = nil
            if let wanted, let image = CloudImage.make(wanted) {
                let overlay = CloudFieldOverlay(field: wanted, image: image)
                cloudOverlay = overlay
                map.addOverlay(overlay, level: .aboveLabels)
            }
            if let old { map.removeOverlay(old) }      // after adding the new one, so it doesn't flash
        }

        private func syncHeatmap(_ map: MKMapView) {
            let wanted = parent.showHeatmap ? parent.lightReadings : []
            guard wanted != (heatmapOverlay?.readings ?? []) else { return }
            if let heatmapOverlay { map.removeOverlay(heatmapOverlay) }
            heatmapOverlay = nil
            guard !wanted.isEmpty else { return }
            let overlay = LightReadingsOverlay(readings: wanted)
            heatmapOverlay = overlay
            map.addOverlay(overlay, level: .aboveRoads)
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
            let savedCentre = parent.isSavedLocation ? parent.centre : nil
            let spotPart: String = spotIDs.joined(separator: "|")
            var savedPart = ""
            if let savedCentre { savedPart = "\(savedCentre.latitude),\(savedCentre.longitude)" }
            let key = [spotPart, savedPart].joined(separator: "#")
            guard key != annotationKey else { return }
            annotationKey = key

            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            var items: [MKAnnotation] = []
            for (index, spot) in parent.spots.enumerated() {
                items.append(SpotAnnotation(spot: spot, rank: index + 1))
            }
            if let savedCentre { items.append(SavedLocationAnnotation(coordinate: savedCentre)) }
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
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.8)
                renderer.lineWidth = 2
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            if let clouds = overlay as? CloudFieldOverlay {
                return CloudFieldRenderer(overlay: clouds)
            }
            if let heatmap = overlay as? LightReadingsOverlay {
                return LightReadingsRenderer(overlay: heatmap)
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
                view.glyphText = "\(spotAnnotation.rank)"
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }

            if let saved = annotation as? SavedLocationAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "saved") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: saved, reuseIdentifier: "saved")
                view.annotation = saved
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
    }
}
