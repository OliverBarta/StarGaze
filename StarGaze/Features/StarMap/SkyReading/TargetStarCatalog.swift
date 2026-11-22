import Foundation

/// Looks up a constellation's stick-figure stars in the bundled star catalog, for Gemini's context.
enum TargetStarCatalog {
    /// Stick-figure vertices this close (degrees) to a catalog star are that star.
    nonisolated static let matchToleranceDegrees = 0.05

    /// The constellation's brightest stick-figure stars, brightest first.
    static func brightestStars(constellationID: String, limit: Int) -> [SkyAnalysisStar] {
        guard let constellation = SkyCatalog.constellations.first(where: { $0.id == constellationID }) else {
            return []
        }
        let vertices = constellation.lines.flatMap { $0 }
        return brightestStars(vertices: vertices, field: SkyArt.fieldStars,
                              named: SkyArt.namedStars.map { ($0.name, $0.ra, $0.dec) }, limit: limit)
    }

    /// Pure matching: each unique vertex [ra, dec] to its catalog magnitude and optional name.
    nonisolated static func brightestStars(vertices: [[Double]], field: [[Double]],
                                           named: [(name: String, ra: Double, dec: Double)],
                                           limit: Int) -> [SkyAnalysisStar] {
        var found: [(ra: Double, dec: Double, star: SkyAnalysisStar)] = []
        for vertex in vertices where vertex.count >= 2 {
            let ra = vertex[0], dec = vertex[1]
            if found.contains(where: { separation(ra, dec, $0.ra, $0.dec) < matchToleranceDegrees }) { continue }
            guard let match = field.first(where: {
                $0.count >= 3 && separation(ra, dec, $0[0], $0[1]) < matchToleranceDegrees
            }) else { continue }
            let name = named.first { separation(ra, dec, $0.ra, $0.dec) < matchToleranceDegrees }?.name
            found.append((ra, dec, SkyAnalysisStar(name: name, magnitude: match[2])))
        }
        return Array(found.map(\.star).sorted { $0.magnitude < $1.magnitude }.prefix(limit))
    }

    /// Small-angle separation in degrees (fine at the 0.05° scale used here).
    nonisolated private static func separation(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
        var dRA = abs(ra1 - ra2)
        if dRA > 180 { dRA = 360 - dRA }
        let cosDec = cos((dec1 + dec2) / 2 * .pi / 180)
        return hypot(dRA * cosDec, dec1 - dec2)
    }
}
