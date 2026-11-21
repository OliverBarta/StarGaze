//
//  TonightConditionsService.swift
//  Stargazing Spots feature
//
//  The live "tonight" layer:
//    - Sun and Moon positions + Moon phase, calculated on the phone (no network)
//    - Cloud cover forecast from Open-Meteo (free, no API key) for a grid of
//      points around the search centre — one request, cached for 30 minutes
//    - Tonight's score 0–100 per spot and hour, with a one-line reason
//
//  Astronomy: low-precision formulas (as used by the open-source SunCalc
//  library, based on Meeus) — accurate to a fraction of a degree, plenty here.
//  Weather data by Open-Meteo.com (CC BY 4.0).
//

import Foundation
import CoreLocation
import Observation

// MARK: - Astronomy (offline)

nonisolated struct SkyAstronomy: Sendable, Equatable {
    let sunAltitudeDeg: Double
    let moonAltitudeDeg: Double
    /// 0 = new moon (dark), 1 = full moon.
    let moonIllumination: Double
    /// 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    let moonPhase: Double

    var moonIsUp: Bool { moonAltitudeDeg > 0 }
    var isAstronomicallyDark: Bool { sunAltitudeDeg <= -18 }

    var moonPhaseName: String {
        switch moonPhase {
        case ..<0.03, 0.97...: "New Moon"
        case ..<0.22: "Waxing crescent"
        case ..<0.28: "First quarter"
        case ..<0.47: "Waxing gibbous"
        case ..<0.53: "Full Moon"
        case ..<0.72: "Waning gibbous"
        case ..<0.78: "Last quarter"
        default: "Waning crescent"
        }
    }
}

nonisolated enum Astronomy {
    private static let rad = Double.pi / 180
    private static let obliquity = rad * 23.4397

    static func sky(at date: Date, latitude: Double, longitude: Double) -> SkyAstronomy {
        let d = days(date)
        let lw = rad * -longitude, phi = rad * latitude

        let sun = sunCoords(d)
        let sunAlt = altitude(sidereal(d, lw) - sun.ra, phi, sun.dec)

        let moon = moonCoords(d)
        let moonAlt = altitude(sidereal(d, lw) - moon.ra, phi, moon.dec)

        // Moon illumination (fraction lit) and phase
        let sunDist = 149_598_000.0
        let elong = acos(sin(sun.dec) * sin(moon.dec) + cos(sun.dec) * cos(moon.dec) * cos(sun.ra - moon.ra))
        let inc = atan2(sunDist * sin(elong), moon.dist - sunDist * cos(elong))
        let angle = atan2(cos(sun.dec) * sin(sun.ra - moon.ra),
                          sin(sun.dec) * cos(moon.dec) - cos(sun.dec) * sin(moon.dec) * cos(sun.ra - moon.ra))
        let fraction = (1 + cos(inc)) / 2
        let phase = 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / .pi

        return SkyAstronomy(sunAltitudeDeg: sunAlt / rad, moonAltitudeDeg: moonAlt / rad,
                            moonIllumination: fraction, moonPhase: phase)
    }

    private static func days(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 0.5 + 2_440_588 - 2_451_545
    }
    private static func rightAscension(_ l: Double, _ b: Double) -> Double {
        atan2(sin(l) * cos(obliquity) - tan(b) * sin(obliquity), cos(l))
    }
    private static func declination(_ l: Double, _ b: Double) -> Double {
        asin(sin(b) * cos(obliquity) + cos(b) * sin(obliquity) * sin(l))
    }
    private static func altitude(_ h: Double, _ phi: Double, _ dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
    }
    private static func sidereal(_ d: Double, _ lw: Double) -> Double {
        rad * (280.16 + 360.985_623_5 * d) - lw
    }
    private static func sunCoords(_ d: Double) -> (dec: Double, ra: Double) {
        let m = rad * (357.5291 + 0.985_600_28 * d)
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let l = m + c + rad * 102.9372 + .pi
        return (declination(l, 0), rightAscension(l, 0))
    }
    private static func moonCoords(_ d: Double) -> (ra: Double, dec: Double, dist: Double) {
        let l0 = rad * (218.316 + 13.176_396 * d)
        let m = rad * (134.963 + 13.064_993 * d)
        let f = rad * (93.272 + 13.229_350 * d)
        let l = l0 + rad * 6.289 * sin(m)
        let b = rad * 5.128 * sin(f)
        let dist = 385_001 - 20_905 * cos(m)
        return (rightAscension(l, b), declination(l, b), dist)
    }
}

// MARK: - Tonight's score

nonisolated struct TonightScore: Sendable, Equatable {
    let score: Int                 // 0...100
    let reason: String             // e.g. "Dark sky (Bortle 3) but 80% cloud"
    let cloudPercent: Double?      // nil = no forecast (offline)
    let sky: SkyAstronomy
}

nonisolated enum TonightScoring {
    /// Combines darkness of the site, cloud, Moon and twilight into 0–100.
    /// Each factor is 0...1 and they multiply: any one of them can ruin a night.
    static func score(reading: SkyReading, cloudPercent: Double?, sky: SkyAstronomy) -> TonightScore {
        // Site darkness: SQM 18 (city) -> 0, SQM 22 (pristine) -> 1
        let dark = min(1, max(0, (reading.sqm - 18) / 4))
        // Cloud: 0% -> 1, 100% -> 0
        let cloudFactor = cloudPercent.map { 1 - min(100, max(0, $0)) / 100 } ?? 1
        // Moon: a full Moon high in the sky costs 60%; a set or new Moon costs nothing
        let moonStrength = sky.moonIsUp
            ? sky.moonIllumination * min(1, (sky.moonAltitudeDeg / 30).squareRoot())
            : 0
        let moonFactor = 1 - 0.6 * moonStrength
        // Twilight: fully dark when the Sun is 18° below the horizon, useless above -6°
        let twilightFactor = min(1, max(0, (-6 - sky.sunAltitudeDeg) / 12))

        let value = Int((100 * dark * cloudFactor * moonFactor * twilightFactor).rounded())

        // One-line reason: what's good, then what's limiting it
        var problems: [String] = []
        if sky.sunAltitudeDeg > -6 {
            problems.append("the Sun is barely down")
        } else if twilightFactor < 1 {
            problems.append("twilight, not fully dark yet")
        }
        if let c = cloudPercent, c >= 50 { problems.append("\(Int(c.rounded()))% cloud") }
        if moonStrength >= 0.3 {
            problems.append("bright Moon (\(Int((sky.moonIllumination * 100).rounded()))% lit)")
        }
        if dark < 0.5 { problems.append("light-polluted sky (Bortle \(reading.bortle))") }

        var reason: String
        if dark >= 0.7 {
            reason = "Dark sky (Bortle \(reading.bortle))"
            reason += problems.isEmpty ? (cloudPercent == nil ? "" : ", clear, no bright Moon")
                                       : " but " + problems.joined(separator: " and ")
        } else if problems.isEmpty {
            reason = "Clear, but some light pollution (Bortle \(reading.bortle))"
        } else {
            let text = problems.joined(separator: " and ")
            reason = text.prefix(1).uppercased() + text.dropFirst()
        }
        if cloudPercent == nil { reason += " · no cloud forecast" }

        return TonightScore(score: value, reason: reason, cloudPercent: cloudPercent, sky: sky)
    }
}

// MARK: - Cloud grid (Open-Meteo)

/// One coloured square of the cloud overlay.
nonisolated struct CloudCell: Identifiable, Equatable, Sendable {
    let id: Int
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    let cover: Double              // 0...100 %
}

nonisolated struct CloudGrid: Sendable {
    let lats: [Double]             // row centres, south -> north
    let lons: [Double]             // column centres, west -> east
    let times: [Date]
    /// cover[pointIndex][timeIndex], pointIndex = row * lons.count + col
    let cover: [[Double?]]
    let fetchedAt: Date
    let key: String

    private var latStep: Double { lats.count > 1 ? lats[1] - lats[0] : 1 }
    private var lonStep: Double { lons.count > 1 ? lons[1] - lons[0] : 1 }

    func timeIndex(for date: Date) -> Int? {
        guard let best = times.indices.min(by: {
            abs(times[$0].timeIntervalSince(date)) < abs(times[$1].timeIntervalSince(date))
        }), abs(times[best].timeIntervalSince(date)) <= 90 * 60 else { return nil }
        return best
    }

    /// Cloud % at the grid point nearest to `c` (nil if outside the grid or no data).
    func cover(at c: CLLocationCoordinate2D, time: Date) -> Double? {
        guard let t = timeIndex(for: time), !lats.isEmpty, !lons.isEmpty else { return nil }
        let row = Int(((c.latitude - lats[0]) / latStep).rounded())
        let col = Int(((c.longitude - lons[0]) / lonStep).rounded())
        guard (0..<lats.count).contains(row), (0..<lons.count).contains(col) else { return nil }
        return cover[row * lons.count + col][t]
    }

    func cells(at time: Date) -> [CloudCell] {
        guard let t = timeIndex(for: time) else { return [] }
        var out: [CloudCell] = []
        for row in lats.indices {
            for col in lons.indices {
                let i = row * lons.count + col
                guard let value = cover[i][t] else { continue }
                out.append(CloudCell(id: i,
                                     minLat: lats[row] - latStep / 2, maxLat: lats[row] + latStep / 2,
                                     minLon: lons[col] - lonStep / 2, maxLon: lons[col] + lonStep / 2,
                                     cover: value))
            }
        }
        return out
    }
}

private nonisolated struct OpenMeteoPoint: Decodable, Sendable {
    let hourly: Hourly
    nonisolated struct Hourly: Decodable, Sendable {
        let time: [Double]                 // unix seconds (timeformat=unixtime)
        let cloud_cover: [Double?]
    }
}

// MARK: - Service

@MainActor
@Observable
final class TonightConditionsService {

    private(set) var cloudGrid: CloudGrid?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// Points per side of the cloud grid (9 x 9 = 81 points, one request).
    private let gridSize = 9
    private let maxAge: TimeInterval = 30 * 60

    init() {}

    /// Fetches cloud cover for a grid covering `radiusKm` around `centre`.
    /// Cached: does nothing if the same area was fetched in the last 30 minutes.
    func refreshClouds(around centre: CLLocationCoordinate2D, radiusKm: Double) async {
        let key = String(format: "%.1f,%.1f,%.0f", centre.latitude, centre.longitude, radiusKm)
        if let grid = cloudGrid, grid.key == key, Date().timeIntervalSince(grid.fetchedAt) < maxAge { return }

        // grid slightly larger than the search circle so the overlay covers the view
        let span = radiusKm * 1.3
        let latSpan = span / 111.32
        let lonSpan = span / (111.32 * max(0.01, cos(centre.latitude * .pi / 180)))
        let n = gridSize
        let lats = (0..<n).map { centre.latitude - latSpan + 2 * latSpan * Double($0) / Double(n - 1) }
        let lons = (0..<n).map { centre.longitude - lonSpan + 2 * lonSpan * Double($0) / Double(n - 1) }

        var latList: [String] = [], lonList: [String] = []
        for lat in lats {
            for lon in lons {
                latList.append(String(format: "%.4f", lat))
                lonList.append(String(format: "%.4f", lon))
            }
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: latList.joined(separator: ",")),
            .init(name: "longitude", value: lonList.joined(separator: ",")),
            .init(name: "hourly", value: "cloud_cover"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "past_days", value: "1"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        guard let url = components.url else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                lastError = "Cloud forecast unavailable right now."
                return
            }
            // several coordinates -> JSON array; one coordinate -> a single object
            let points: [OpenMeteoPoint]
            if let array = try? JSONDecoder().decode([OpenMeteoPoint].self, from: data) {
                points = array
            } else {
                points = [try JSONDecoder().decode(OpenMeteoPoint.self, from: data)]
            }
            guard points.count == n * n, let first = points.first else {
                lastError = "Unexpected cloud forecast format."
                return
            }
            cloudGrid = CloudGrid(
                lats: lats, lons: lons,
                times: first.hourly.time.map { Date(timeIntervalSince1970: $0) },
                cover: points.map { $0.hourly.cloud_cover },
                fetchedAt: Date(), key: key)
            lastError = nil
        } catch {
            lastError = "Offline: no cloud forecast. Darkness and Moon still shown."
        }
    }

    func cloudCover(at c: CLLocationCoordinate2D, time: Date) -> Double? {
        cloudGrid?.cover(at: c, time: time)
    }

    func cloudCells(at time: Date) -> [CloudCell] {
        cloudGrid?.cells(at: time) ?? []
    }

    func sky(at c: CLLocationCoordinate2D, time: Date) -> SkyAstronomy {
        Astronomy.sky(at: time, latitude: c.latitude, longitude: c.longitude)
    }

    func score(for spot: StargazingSpot, at time: Date) -> TonightScore {
        TonightScoring.score(reading: spot.reading,
                             cloudPercent: cloudCover(at: spot.coordinate, time: time),
                             sky: sky(at: spot.coordinate, time: time))
    }

    /// The hour with the highest score for this spot.
    func bestHour(for spot: StargazingSpot, in hours: [Date]) -> (time: Date, score: TonightScore)? {
        hours.map { ($0, score(for: spot, at: $0)) }.max { $0.1.score < $1.1.score }
    }

    /// Whole hours for "tonight" in the device's time zone:
    /// from 6 pm (or now, if later) until 6 am. Before 6 am it's the rest of the current night.
    static func nightHours(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let startOfDay = calendar.startOfDay(for: now)
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let start: Date, end: Date
        if calendar.component(.hour, from: now) < 6 {
            start = thisHour
            end = calendar.date(byAdding: .hour, value: 6, to: startOfDay)!
        } else {
            start = max(thisHour, calendar.date(byAdding: .hour, value: 18, to: startOfDay)!)
            end = calendar.date(byAdding: .hour, value: 30, to: startOfDay)!
        }
        var hours: [Date] = []
        var t = start
        while t <= end {
            hours.append(t)
            t = t.addingTimeInterval(3600)
        }
        return hours
    }
}
