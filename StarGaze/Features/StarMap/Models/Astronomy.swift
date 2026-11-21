import Foundation
import simd

/// The math that turns a star's fixed sky coordinates (RA/Dec) into
/// "where is it right now from here" (altitude/azimuth).
enum Astronomy {
    /// Returns altitude (degrees above the horizon) and azimuth
    /// (degrees clockwise from true north: east = 90, south = 180).
    static func altAz(raDeg: Double, decDeg: Double,
                      latDeg: Double, lonDeg: Double, date: Date) -> (alt: Double, az: Double) {
        // Julian date and Greenwich sidereal time (how far the Earth has spun)
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        var gmst = (280.46061837 + 360.98564736629 * (jd - 2451545)).truncatingRemainder(dividingBy: 360)
        if gmst < 0 { gmst += 360 }

        // Hour angle: how far the star is past your local meridian
        let ha = (gmst + lonDeg - raDeg) * .pi / 180
        let dec = decDeg * .pi / 180
        let lat = latDeg * .pi / 180

        let alt = asin(sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(ha))
        let az = atan2(-sin(ha) * cos(dec),
                       cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(ha))

        var azDeg = az * 180 / .pi
        if azDeg < 0 { azDeg += 360 }
        return (alt * 180 / .pi, azDeg)
    }

    /// Unit vector pointing at (alt, az) in ARKit's .gravityAndHeading world:
    /// +x = east, +y = up, -z = true north.
    static func arDirection(altDeg: Double, azDeg: Double) -> SIMD3<Float> {
        let alt = altDeg * .pi / 180
        let az = azDeg * .pi / 180
        let east = cos(alt) * sin(az)
        let up = sin(alt)
        let north = cos(alt) * cos(az)
        return SIMD3<Float>(Float(east), Float(up), Float(-north))
    }

    static func compassName(azDeg: Double) -> String {
        let names = ["north", "northeast", "east", "southeast",
                     "south", "southwest", "west", "northwest"]
        let i = Int((azDeg + 22.5) / 45) % 8
        return names[i]
    }
}

/// A constellation placed in tonight's sky for a given place and time.
struct PlacedConstellation: Identifiable {
    let id: String
    let name: String
    let rank: Int
    let segments: [[SIMD3<Float>]]  // unit direction vectors, ARKit world space
    let center: SIMD3<Float>        // average direction of its stars
    let centerAlt: Double
    let centerAz: Double
    let art: ArtEntry?
    let artGrid: [SIMD3<Float>]     // illustration mesh corners on the sky

    var isAboveHorizon: Bool { centerAlt > 0 }

    var directionText: String {
        "\(Int(centerAlt.rounded()))° up, \(Astronomy.compassName(azDeg: centerAz))"
    }
}

enum SkyModel {
    static func place(latDeg: Double, lonDeg: Double, date: Date) -> [PlacedConstellation] {
        var result: [PlacedConstellation] = []
        let catalog = SkyCatalog.constellations

        for c in 0..<catalog.count {
            let constellation = catalog[c]
            var segments: [[SIMD3<Float>]] = []
            var sum = SIMD3<Float>(0, 0, 0)

            for s in 0..<constellation.lines.count {
                let segment = constellation.lines[s]
                var points: [SIMD3<Float>] = []
                for i in 0..<segment.count {
                    let pos = Astronomy.altAz(raDeg: segment[i][0], decDeg: segment[i][1],
                                              latDeg: latDeg, lonDeg: lonDeg, date: date)
                    let v = Astronomy.arDirection(altDeg: pos.alt, azDeg: pos.az)
                    points.append(v)
                    sum += v
                }
                segments.append(points)
            }

            guard simd_length(sum) > 0 else { continue }
            let center = simd_normalize(sum)
            let alt = asin(Double(center.y)) * 180 / .pi
            var az = atan2(Double(center.x), Double(-center.z)) * 180 / .pi
            if az < 0 { az += 360 }

            // illustration mesh: each corner's RA/Dec -> where it is right now
            let art = SkyArt.entries[constellation.id]
            var artGrid: [SIMD3<Float>] = []
            if let art {
                for g in 0..<art.radec.count {
                    let pos = Astronomy.altAz(raDeg: art.radec[g][0], decDeg: art.radec[g][1],
                                              latDeg: latDeg, lonDeg: lonDeg, date: date)
                    artGrid.append(Astronomy.arDirection(altDeg: pos.alt, azDeg: pos.az))
                }
            }

            result.append(PlacedConstellation(id: constellation.id, name: constellation.name,
                                              rank: constellation.rank, segments: segments,
                                              center: center, centerAlt: alt, centerAz: az,
                                              art: art, artGrid: artGrid))
        }
        return result
    }
}
