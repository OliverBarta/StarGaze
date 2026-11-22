//
//  LightPollutionService.swift
//  Stargazing Spots feature
//
//  Loads light-pollution tiles (bundled -> disk cache -> download), looks up the
//  sky brightness at a coordinate, finds the darkest spots near the user, and
//  renders a colour image per tile for the map overlay.
//
//  Data: Falchi et al. 2016, World Atlas of Artificial Night Sky Brightness
//  (CC BY-NC 4.0), preprocessed by make_light_tiles.py.
//
//  TILE FORMAT (must match make_light_tiles.py):
//    "<lat0>_<lon0>.bin", SW corner, 5° x 5°, raw DEFLATE of 400*400 bytes,
//    row 0 = north, col 0 = west. byte 0 = water/no data,
//    byte v >= 1  ->  SQM = 16.0 + (v - 1) * 0.025  (mag/arcsec²)
//

import Foundation
import CoreLocation
import CoreGraphics
import Observation

// MARK: - Bortle scale

nonisolated enum Bortle {
    /// A cell is Bortle `k` if its SQM >= the value. Darker than nothing listed -> 9.
    /// Keep in sync with BORTLE_SQM_MIN in make_light_tiles.py.
    static let sqmMinimum: [(bortle: Int, sqm: Double)] = [
        (1, 21.75), (2, 21.60), (3, 21.30), (4, 20.80),
        (5, 20.30), (6, 19.25), (7, 18.50), (8, 18.00),
    ]

    static func fromSQM(_ sqm: Double) -> Int {
        for entry in sqmMinimum where sqm >= entry.sqm { return entry.bortle }
        return 9
    }

    static func label(_ bortle: Int) -> String {
        switch bortle {
        case 1: "Excellent dark-sky site"
        case 2: "Truly dark site"
        case 3: "Rural sky"
        case 4: "Rural / suburban transition"
        case 5: "Suburban sky"
        case 6: "Bright suburban sky"
        case 7: "Suburban / urban transition"
        case 8: "City sky"
        default: "Inner-city sky"
        }
    }

    /// Spot colours: dark blue (dark sky) -> yellow -> red (city).
    static func rgb(_ bortle: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch bortle {
        case 1: (8, 16, 60)
        case 2: (20, 40, 110)
        case 3: (30, 80, 170)
        case 4: (40, 150, 120)
        case 5: (140, 190, 60)
        case 6: (240, 220, 60)
        case 7: (250, 160, 40)
        case 8: (240, 80, 30)
        default: (200, 20, 40)
        }
    }
}

// MARK: - Tile model

nonisolated struct TileKey: Hashable, Sendable, CustomStringConvertible {
    static let degrees = 5

    let lat0: Int   // south edge
    let lon0: Int   // west edge

    init(lat0: Int, lon0: Int) { self.lat0 = lat0; self.lon0 = lon0 }

    init(containing c: CLLocationCoordinate2D) {
        let d = Double(Self.degrees)
        lat0 = Int((c.latitude / d).rounded(.down)) * Self.degrees
        lon0 = Int((c.longitude / d).rounded(.down)) * Self.degrees
    }

    var name: String { "\(lat0)_\(lon0)" }
    var description: String { name }
}

nonisolated struct LightTile: Sendable {
    static let cells = 400
    static let sqmBase = 16.0
    static let sqmStep = 0.025

    let key: TileKey
    /// cells*cells bytes, or EMPTY for an all-water (ocean) tile.
    let values: [UInt8]

    var isOcean: Bool { values.isEmpty }
    static var cellDegrees: Double { Double(TileKey.degrees) / Double(cells) }

    var south: Double { Double(key.lat0) }
    var north: Double { Double(key.lat0 + TileKey.degrees) }
    var west: Double { Double(key.lon0) }
    var east: Double { Double(key.lon0 + TileKey.degrees) }

    static func sqm(fromByte v: UInt8) -> Double? {
        v == 0 ? nil : sqmBase + Double(Int(v) - 1) * sqmStep
    }

    /// Raw byte at a coordinate (0 = water / no data). nil if outside this tile.
    func byte(at c: CLLocationCoordinate2D) -> UInt8? {
        guard c.latitude >= south, c.latitude < north,
              c.longitude >= west, c.longitude < east else { return nil }
        if isOcean { return 0 }
        let row = min(Self.cells - 1, Int((north - c.latitude) / Self.cellDegrees))
        let col = min(Self.cells - 1, Int((c.longitude - west) / Self.cellDegrees))
        return values[row * Self.cells + col]
    }

    func centre(row: Int, col: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: north - (Double(row) + 0.5) * Self.cellDegrees,
                               longitude: west + (Double(col) + 0.5) * Self.cellDegrees)
    }
}

// MARK: - Results

nonisolated struct SkyReading: Sendable, Equatable {
    let sqm: Double          // mag/arcsec², higher = darker
    let bortle: Int          // 1...9
}

nonisolated struct StargazingSpot: Identifiable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let sqm: Double
    let bortle: Int
    /// Straight-line ("as the crow flies") distance from the search centre.
    let straightLineKm: Double

    var id: String { String(format: "%.4f,%.4f", latitude, longitude) }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var reading: SkyReading { SkyReading(sqm: sqm, bortle: bortle) }
}

private nonisolated struct TileIndex: Decodable, Sendable {
    let version: Int
    let tileDeg: Int
    let cells: Int
    let tiles: [String]
}

// MARK: - Service

@MainActor
@Observable
final class LightPollutionService {

    /// Loaded tiles. The map view watches this to add overlays.
    private(set) var tiles: [TileKey: LightTile] = [:]
    private(set) var isLoading = false
    /// Tiles we needed but couldn't get (offline, or not hosted yet).
    private(set) var missingTiles: Set<TileKey> = []

    /// Folder URL that holds index.json and the .bin tiles, e.g.
    /// https://<user>.github.io/<repo>/LightTiles/   — nil = bundled data only.
    let remoteBaseURL: URL?

    @ObservationIgnored private var index: Set<String>?
    @ObservationIgnored private var lastIndexAttempt: Date?
    private let session: URLSession

    init(remoteBaseURL: URL? = nil) {
        self.remoteBaseURL = remoteBaseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: Loading

    /// Makes sure every tile within `radiusKm` of `centre` is loaded.
    /// Bundled and cached tiles work offline; others are downloaded if possible.
    func loadTiles(around centre: CLLocationCoordinate2D, radiusKm: Double) async {
        let needed = Self.tileKeys(around: centre, radiusKm: radiusKm)
            .filter { tiles[$0] == nil }
        guard !needed.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        for key in needed {
            if let tile = await loadTile(key) {
                tiles[key] = tile
                missingTiles.remove(key)
            } else {
                missingTiles.insert(key)
            }
        }
    }

    private func loadTile(_ key: TileKey) async -> LightTile? {
        // 1. bundled with the app (Southern Ontario)
        if let url = Bundle.main.url(forResource: key.name, withExtension: "bin", subdirectory: "LightTiles")
            ?? Bundle.main.url(forResource: key.name, withExtension: "bin"),
           let tile = Self.decode(key: key, data: try? Data(contentsOf: url)) {
            return tile
        }
        // 2. downloaded earlier
        let cached = Self.cacheURL(key.name + ".bin")
        if let tile = Self.decode(key: key, data: try? Data(contentsOf: cached)) {
            return tile
        }
        // 3. a tile missing from the index is open water (no land -> never generated)
        guard let index = await loadIndex() else { return nil }
        guard index.contains(key.name) else { return LightTile(key: key, values: []) }
        // 4. listed but not on the phone: download it (only if hosting is configured)
        guard let base = remoteBaseURL else { return nil }
        do {
            let (data, response) = try await session.data(from: base.appending(path: key.name + ".bin"))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let tile = Self.decode(key: key, data: data) else { return nil }
            try? data.write(to: cached, options: .atomic)
            return tile
        } catch {
            return nil
        }
    }

    /// index.json bundled with the app (all tiles bundled), else from the server
    /// (refreshed once per launch), else the cached copy.
    private func loadIndex() async -> Set<String>? {
        if let index { return index }
        if let url = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "LightTiles")
            ?? Bundle.main.url(forResource: "index", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(TileIndex.self, from: data) {
            index = Set(decoded.tiles)
            return index
        }
        if let last = lastIndexAttempt, Date().timeIntervalSince(last) < 60 {
            return Self.readCachedIndex()      // don't hammer the network while offline
        }
        lastIndexAttempt = Date()
        guard let base = remoteBaseURL else { return Self.readCachedIndex() }
        do {
            let (data, response) = try await session.data(from: base.appending(path: "index.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return Self.readCachedIndex() }
            let decoded = try JSONDecoder().decode(TileIndex.self, from: data)
            try? data.write(to: Self.cacheURL("index.json"), options: .atomic)
            index = Set(decoded.tiles)
            return index
        } catch {
            return Self.readCachedIndex()
        }
    }

    private static func readCachedIndex() -> Set<String>? {
        guard let data = try? Data(contentsOf: cacheURL("index.json")),
              let decoded = try? JSONDecoder().decode(TileIndex.self, from: data) else { return nil }
        return Set(decoded.tiles)
    }

    private static func decode(key: TileKey, data: Data?) -> LightTile? {
        guard let data,
              let raw = try? (data as NSData).decompressed(using: .zlib) as Data,
              raw.count == LightTile.cells * LightTile.cells else { return nil }
        return LightTile(key: key, values: [UInt8](raw))
    }

    private static func cacheURL(_ file: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "LightTiles", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: file)
    }

    // MARK: Lookup

    /// Sky brightness at a coordinate. nil = water, or tile not loaded.
    func reading(at c: CLLocationCoordinate2D) -> SkyReading? {
        guard let tile = tiles[TileKey(containing: c)],
              let byte = tile.byte(at: c),
              let sqm = LightTile.sqm(fromByte: byte) else { return nil }
        return SkyReading(sqm: sqm, bortle: Bortle.fromSQM(sqm))
    }

    // MARK: Best spots

    /// Best land cells within `radiusKm`, spread at least `minSeparationKm` apart, ranked by
    /// darkness x cloud (the same factors as Tonight's score). `cloudCover` gives the cloud %
    /// at a coordinate, or nil when there's no forecast (then only darkness counts).
    /// Spots within `similarDarknessMag` of each other are ranked nearest-first,
    /// so we don't send people far away for a 0.02 mag gain.
    /// Call `loadTiles(around:radiusKm:)` first.
    func findDarkSpots(near centre: CLLocationCoordinate2D,
                       radiusKm: Double,
                       count: Int = 3,
                       minSeparationKm: Double = 10,
                       similarDarknessMag: Double = 0.1,
                       cloudCover: (CLLocationCoordinate2D) -> Double? = { _ in nil }) -> [StargazingSpot] {
        let latSpan = radiusKm / 111.32
        let lonSpan = radiusKm / (111.32 * max(0.01, cos(centre.latitude * .pi / 180)))
        let minLat = centre.latitude - latSpan, maxLat = centre.latitude + latSpan
        let minLon = centre.longitude - lonSpan, maxLon = centre.longitude + lonSpan
        let n = LightTile.cells, cd = LightTile.cellDegrees

        struct Candidate { let byte: UInt8; let quality: Double; let lat: Double; let lon: Double; let km: Double }
        var candidates: [Candidate] = []

        for key in Self.tileKeys(around: centre, radiusKm: radiusKm) {
            guard let tile = tiles[key], !tile.isOcean else { continue }
            // row/col range of this tile that overlaps the search box
            let r0 = max(0, Int((tile.north - maxLat) / cd))
            let r1 = min(n - 1, Int((tile.north - minLat) / cd))
            let c0 = max(0, Int((minLon - tile.west) / cd))
            let c1 = min(n - 1, Int((maxLon - tile.west) / cd))
            guard r0 <= r1, c0 <= c1 else { continue }

            for row in r0...r1 {
                let lat = tile.north - (Double(row) + 0.5) * cd
                for col in c0...c1 {
                    let byte = tile.values[row * n + col]
                    guard byte > 0 else { continue }              // water
                    let lon = tile.west + (Double(col) + 0.5) * cd
                    let km = Self.distanceKm(centre.latitude, centre.longitude, lat, lon)
                    guard km <= radiusKm else { continue }
                    let sqm = LightTile.sqm(fromByte: byte)!
                    let cloud = cloudCover(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    let quality = TonightScoring.darknessFactor(sqm: sqm) * TonightScoring.cloudFactor(cloud)
                    candidates.append(Candidate(byte: byte, quality: quality, lat: lat, lon: lon, km: km))
                }
            }
        }

        // best darkness x cloud first, then darkest, then nearest. Both are compared in buckets
        // the size of `similarDarknessMag`; darkness alone breaks ties when the quality is 0
        // (all cells brighter than SQM 18, or 100% cloud everywhere).
        let bucketBytes = max(1, Int((similarDarknessMag / LightTile.sqmStep).rounded()))
        let qualityBucket = similarDarknessMag / 4        // darknessFactor gains 1 per 4 mag
        candidates.sort {
            let qa = Int($0.quality / qualityBucket), qb = Int($1.quality / qualityBucket)
            if qa != qb { return qa > qb }
            let a = Int($0.byte) / bucketBytes, b = Int($1.byte) / bucketBytes
            return a != b ? a > b : $0.km < $1.km
        }

        // greedy pick: skip anything too close to a spot we already chose
        var picked: [StargazingSpot] = []
        for c in candidates {
            if picked.contains(where: {
                Self.distanceKm($0.latitude, $0.longitude, c.lat, c.lon) < minSeparationKm
            }) { continue }
            let sqm = LightTile.sqm(fromByte: c.byte)!
            picked.append(StargazingSpot(latitude: c.lat, longitude: c.lon, sqm: sqm,
                                         bortle: Bortle.fromSQM(sqm), straightLineKm: c.km))
            if picked.count == count { break }
        }
        return picked
    }

    // MARK: Geometry helpers

    /// Every tile touching the box around `centre` ± `radiusKm`.
    nonisolated static func tileKeys(around centre: CLLocationCoordinate2D, radiusKm: Double) -> [TileKey] {
        let latSpan = radiusKm / 111.32
        let lonSpan = radiusKm / (111.32 * max(0.01, cos(centre.latitude * .pi / 180)))
        let sw = TileKey(containing: .init(latitude: max(-89.9, centre.latitude - latSpan),
                                           longitude: centre.longitude - lonSpan))
        let ne = TileKey(containing: .init(latitude: min(89.9, centre.latitude + latSpan),
                                           longitude: centre.longitude + lonSpan))
        var keys: [TileKey] = []
        for lat0 in stride(from: sw.lat0, through: ne.lat0, by: TileKey.degrees) {
            for lon0 in stride(from: sw.lon0, through: ne.lon0, by: TileKey.degrees) {
                keys.append(TileKey(lat0: lat0, lon0: lon0))
            }
        }
        return keys
    }

    /// Great-circle distance in km (haversine).
    nonisolated static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0, d2r = Double.pi / 180
        let dLat = (lat2 - lat1) * d2r, dLon = (lon2 - lon1) * d2r
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * d2r) * cos(lat2 * d2r) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
