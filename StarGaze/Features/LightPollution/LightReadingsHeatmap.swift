//
//  LightReadingsHeatmap.swift
//  Stargazing Spots feature
//
//  Heatmap of the `light_readings` Supabase table. Readings within `radiusKm` of each
//  other blend together (a distance-weighted average), and the colour fades out
//  `radiusKm` from the nearest reading. The renderer draws each map tile on demand at
//  the tile's own resolution, so it stays sharp at any zoom without one huge image.
//

import MapKit

/// One row of `light_readings`: coordinates are a Postgres `point(latitude, longitude)`,
/// which PostgREST sends as the string "(lat,lon)". Strength is 0 (dark) to 1 (bright).
nonisolated struct LightReading: Decodable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let strength: Double

    init(latitude: Double, longitude: Double, strength: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.strength = strength
    }

    private enum CodingKeys: String, CodingKey { case coordinates, strength }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .coordinates)
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .coordinates, in: container,
                                                   debugDescription: "Expected \"(lat,lon)\", got \(text)")
        }
        latitude = parts[0]
        longitude = parts[1]
        strength = min(1, max(0, try container.decode(Double.self, forKey: .strength)))
    }
}

/// The readings, bucketed by 0.25° cells so each pixel only checks the readings near it.
nonisolated final class LightReadingsOverlay: NSObject, MKOverlay, @unchecked Sendable {
    /// Readings closer than this blend together; the heatmap fades out this far from any reading.
    static let radiusKm = 30.0

    let readings: [LightReading]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    private static let cellDegrees = 0.25
    private let cells: [Cell: [LightReading]]

    private struct Cell: Hashable { let lat: Int, lon: Int }

    init(readings: [LightReading]) {
        self.readings = readings
        cells = Dictionary(grouping: readings) { Self.cell(lat: $0.latitude, lon: $0.longitude) }
        // all readings, padded by the fade radius
        var rect = MKMapRect.null
        for r in readings {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: r.latitude, longitude: r.longitude))
            let pad = Self.radiusKm * 1000 * MKMapPointsPerMeterAtLatitude(r.latitude)
            rect = rect.union(MKMapRect(x: p.x - pad, y: p.y - pad, width: 2 * pad, height: 2 * pad))
        }
        boundingMapRect = rect
        coordinate = rect.isNull ? CLLocationCoordinate2D() : MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }

    private static func cell(lat: Double, lon: Double) -> Cell {
        Cell(lat: Int((lat / cellDegrees).rounded(.down)), lon: Int((lon / cellDegrees).rounded(.down)))
    }

    /// Blended strength and coverage (0 past `radiusKm` from every reading, up to 1 on top of one).
    func sample(lat: Double, lon: Double) -> (strength: Double, coverage: Double)? {
        let radius = Self.radiusKm
        let kmPerDegLon = 111.32 * max(0.01, cos(lat * .pi / 180))
        let latSpan = Int((radius / 111.32 / Self.cellDegrees).rounded(.up))
        let lonSpan = Int((radius / kmPerDegLon / Self.cellDegrees).rounded(.up))
        let centre = Self.cell(lat: lat, lon: lon)

        var weightSum = 0.0, valueSum = 0.0
        for dLat in -latSpan...latSpan {
            for dLon in -lonSpan...lonSpan {
                guard let bucket = cells[Cell(lat: centre.lat + dLat, lon: centre.lon + dLon)] else { continue }
                for r in bucket {
                    let dy = (r.latitude - lat) * 111.32
                    let dx = (r.longitude - lon) * kmPerDegLon
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d < radius else { continue }
                    // smooth falloff that stays near full strength over most of the dot,
                    // then fades out: 1 on the reading, 0 at the radius
                    let t = 1 - (d / radius) * (d / radius)
                    let w = t * t
                    weightSum += w
                    valueSum += w * r.strength
                }
            }
        }
        guard weightSum > 0 else { return nil }
        return (valueSum / weightSum, min(1, weightSum))
    }
}

nonisolated final class LightReadingsRenderer: MKOverlayRenderer {
    /// Opacity where the heatmap is fully covered.
    static let maxAlpha = 0.75
    /// Roughly one sample per this many screen points (the image is smoothed when drawn).
    private static let pointsPerSample = 3.0
    private static let maxSamples = 256

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        guard let heatmap = overlay as? LightReadingsOverlay else { return false }
        return mapRect.intersects(heatmap.boundingMapRect)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmap = overlay as? LightReadingsOverlay,
              let image = Self.image(heatmap, mapRect: mapRect, zoomScale: zoomScale) else { return }
        let r = rect(for: mapRect)
        context.saveGState()
        context.translateBy(x: r.minX, y: r.maxY)       // same y-flip as LightTileRenderer
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        context.restoreGState()
    }

    private static func image(_ heatmap: LightReadingsOverlay, mapRect: MKMapRect, zoomScale: MKZoomScale) -> CGImage? {
        let screenWidth = mapRect.width * Double(zoomScale), screenHeight = mapRect.height * Double(zoomScale)
        let w = min(maxSamples, max(2, Int(screenWidth / pointsPerSample)))
        let h = min(maxSamples, max(2, Int(screenHeight / pointsPerSample)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var anything = false

        for y in 0..<h {
            // image row 0 is the top (north) of the map rect
            let mapY = mapRect.minY + (Double(y) + 0.5) / Double(h) * mapRect.height
            for x in 0..<w {
                let mapX = mapRect.minX + (Double(x) + 0.5) / Double(w) * mapRect.width
                let c = MKMapPoint(x: mapX, y: mapY).coordinate
                guard let sample = heatmap.sample(lat: c.latitude, lon: c.longitude) else { continue }
                anything = true
                let (red, green, blue) = color(sample.strength)
                let alpha = sample.coverage * maxAlpha
                let i = (y * w + x) * 4
                // premultiplied alpha
                pixels[i] = UInt8((red * alpha * 255).rounded())
                pixels[i + 1] = UInt8((green * alpha * 255).rounded())
                pixels[i + 2] = UInt8((blue * alpha * 255).rounded())
                pixels[i + 3] = UInt8((alpha * 255).rounded())
            }
        }
        guard anything, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Colour ramp from dark sky to bright city, as RGB 0...1.
    static let ramp: [(Double, Double, Double)] = [
        (0.10, 0.15, 0.45),   // dark: deep blue
        (0.10, 0.55, 0.65),   // teal
        (0.35, 0.75, 0.30),   // green
        (0.95, 0.85, 0.25),   // yellow
        (0.95, 0.45, 0.15),   // orange
        (0.90, 0.15, 0.15),   // red
        (1.00, 0.95, 0.95),   // brightest: near white
    ]

    static func color(_ strength: Double) -> (Double, Double, Double) {
        let position = min(1, max(0, strength)) * Double(ramp.count - 1)
        let i = min(ramp.count - 2, Int(position))
        let t = position - Double(i)
        let a = ramp[i], b = ramp[i + 1]
        return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
}
