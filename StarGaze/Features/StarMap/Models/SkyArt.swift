import UIKit
import simd

// Constellation illustrations by Johan Meuris (Free Art License), from Stellarium's
// "western" sky culture, pre-aligned to real star positions (Data/constellation-art.json).
// Real star field + bright star names from d3-celestial (Data/stars.json).

struct ArtEntry: Decodable {
    let file: String          // image name in the bundle, e.g. "art-ursa-major"
    let size: [Double]        // image width, height in pixels
    let grid: Int             // the image is split into grid × grid cells
    let radec: [[Double]]     // (grid+1)² sky positions [ra, dec] for the cell corners
    let affine: [Double]      // pixel -> normalised 2D figure space (a, b, c, d, tx, ty)
    let lines: [[[Double]]]   // stick figure in the same normalised 2D space
}

struct NamedStar: Decodable {
    let name: String
    let ra: Double
    let dec: Double
    let mag: Double
}

enum SkyArt {
    private struct ArtFile: Decodable { let art: [String: ArtEntry] }
    private struct StarsFile: Decodable {
        let stars: [[Double]]   // [ra, dec, magnitude]
        let named: [NamedStar]
    }

    /// Keyed by constellation id, e.g. "UMa".
    static let entries: [String: ArtEntry] = {
        guard let url = Bundle.main.url(forResource: "constellation-art", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ArtFile.self, from: data) else {
            print("⚠️ constellation-art.json missing from the app bundle")
            return [:]
        }
        return file.art
    }()

    private static let starsFile: StarsFile? = {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ stars.json missing from the app bundle")
            return nil
        }
        return try? JSONDecoder().decode(StarsFile.self, from: data)
    }()

    static var fieldStars: [[Double]] { starsFile?.stars ?? [] }
    static var namedStars: [NamedStar] { starsFile?.named ?? [] }

    private static var imageCache: [String: UIImage] = [:]

    static func image(named file: String) -> UIImage? {
        if let cached = imageCache[file] { return cached }
        guard let url = Bundle.main.url(forResource: file, withExtension: "jpg"),
              let gray = UIImage(contentsOfFile: url.path) else { return nil }
        // The files are greyscale to keep them small; redraw them as plain RGBA, because Metal
        // can't use single-channel sRGB textures (it crashes with "pixelFormat (11)").
        guard let cg = gray.cgImage,
              let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let rgb = ctx.makeImage() else { return nil }
        let image = UIImage(cgImage: rgb)
        imageCache[file] = image
        return image
    }

    /// Art for a constellation by its display name ("Ursa Major").
    static func entry(forName name: String) -> ArtEntry? {
        let catalog = SkyCatalog.constellations
        for i in 0..<catalog.count where catalog[i].name == name {
            return entries[catalog[i].id]
        }
        return nil
    }
}

/// A real star placed in tonight's sky.
struct PlacedStar {
    let direction: SIMD3<Float>
    let mag: Double
    let alt: Double
}

struct PlacedNamedStar {
    let name: String
    let direction: SIMD3<Float>
    let mag: Double
    let alt: Double
}

extension SkyModel {
    static func placeStars(latDeg: Double, lonDeg: Double, date: Date) -> [PlacedStar] {
        let field = SkyArt.fieldStars
        var result: [PlacedStar] = []
        result.reserveCapacity(field.count)
        for i in 0..<field.count {
            let pos = Astronomy.altAz(raDeg: field[i][0], decDeg: field[i][1],
                                      latDeg: latDeg, lonDeg: lonDeg, date: date)
            guard pos.alt > -5 else { continue }
            result.append(PlacedStar(direction: Astronomy.arDirection(altDeg: pos.alt, azDeg: pos.az),
                                     mag: field[i][2], alt: pos.alt))
        }
        return result
    }

    static func placeNamedStars(latDeg: Double, lonDeg: Double, date: Date) -> [PlacedNamedStar] {
        let named = SkyArt.namedStars
        var result: [PlacedNamedStar] = []
        for i in 0..<named.count {
            let s = named[i]
            let pos = Astronomy.altAz(raDeg: s.ra, decDeg: s.dec, latDeg: latDeg, lonDeg: lonDeg, date: date)
            guard pos.alt > -2 else { continue }
            result.append(PlacedNamedStar(name: s.name,
                                          direction: Astronomy.arDirection(altDeg: pos.alt, azDeg: pos.az),
                                          mag: s.mag, alt: pos.alt))
        }
        return result
    }
}
