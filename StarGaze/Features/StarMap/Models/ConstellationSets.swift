import SwiftUI

/// A themed group of constellations. Discover any `required` of them to complete the set
/// and trigger its cutscene.
struct ConstellationSet: Identifiable, Hashable {
    let id: String
    let title: String          // "The Menagerie"
    let tagline: String        // shown under the title in the cutscene
    let tier: String           // the big rarity word, Sol's-RNG style
    let symbol: String         // SF Symbol used on the stamp
    let color: Color
    let members: [String]      // constellation names (must match constellations.json)
    let required: Int

    /// Sol's RNG-style odds shown in the cutscene.
    var odds: String {
        switch tier {
        case "CELESTIAL": "1 in 2,500"
        case "EPIC": "1 in 8,000"
        case "LEGENDARY": "1 in 50,000"
        case "DIVINE": "1 in 250,000"
        default: "1 in 1,000,000"
        }
    }

    static let all: [ConstellationSet] = [
        ConstellationSet(
            id: "menagerie", title: "The Menagerie",
            tagline: "The beasts of the sky gather",
            tier: "MYTHIC", symbol: "pawprint.fill",
            color: Color(red: 0.55, green: 0.95, blue: 0.75),
            members: ["Pegasus", "Ursa Major", "Ursa Minor", "Leo", "Leo Minor", "Taurus", "Aries",
                      "Cancer", "Scorpius", "Capricornus", "Pisces", "Piscis Austrinus", "Cetus",
                      "Canis Major", "Canis Minor", "Lepus", "Cygnus", "Aquila", "Delphinus",
                      "Lacerta", "Vulpecula", "Camelopardalis", "Monoceros", "Lupus", "Lynx",
                      "Columba", "Corvus", "Draco", "Hydra", "Equuleus"],
            required: 5),
        ConstellationSet(
            id: "perseus", title: "The Perseus Saga",
            tagline: "A hero, a princess and the sea monster",
            tier: "LEGENDARY", symbol: "shield.lefthalf.filled",
            color: Color(red: 1.0, green: 0.78, blue: 0.35),
            members: ["Perseus", "Andromeda", "Cassiopeia", "Cepheus", "Cetus", "Pegasus"],
            required: 5),
        ConstellationSet(
            id: "hunt", title: "The Great Hunt",
            tagline: "Orion and his hounds give chase",
            tier: "EPIC", symbol: "scope",
            color: Color(red: 1.0, green: 0.45, blue: 0.45),
            members: ["Orion", "Canis Major", "Canis Minor", "Lepus", "Taurus", "Monoceros", "Scorpius"],
            required: 5),
        ConstellationSet(
            id: "zodiac", title: "The Zodiac Wheel",
            tagline: "The path the Sun walks each year",
            tier: "CELESTIAL", symbol: "sun.max.fill",
            color: Color(red: 0.75, green: 0.6, blue: 1.0),
            members: ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpius",
                      "Sagittarius", "Capricornus", "Aquarius", "Pisces"],
            required: 5),
        ConstellationSet(
            id: "heroes", title: "Heroes & Gods",
            tagline: "Legends set among the stars",
            tier: "DIVINE", symbol: "crown.fill",
            color: Color(red: 0.5, green: 0.8, blue: 1.0),
            members: ["Hercules", "Orion", "Perseus", "Boötes", "Ophiuchus", "Gemini", "Auriga",
                      "Aquarius", "Sagittarius", "Centaurus", "Virgo"],
            required: 5),
    ]
}

/// A constellation's stick figure flattened to 2D (north up, east left, like looking up),
/// scaled to fit a unit box centred on (0, 0). Used to draw figures in the cutscene.
enum ConstellationShape {
    static func segments(for name: String) -> [[CGPoint]] {
        let catalog = SkyCatalog.constellations
        var match: CatalogConstellation?
        for i in 0..<catalog.count where catalog[i].name == name {
            match = catalog[i]
        }
        guard let c = match else { return [] }

        // centre of the figure on the sky
        var sx = 0.0, sy = 0.0, sz = 0.0
        for s in 0..<c.lines.count {
            for p in 0..<c.lines[s].count {
                let ra = c.lines[s][p][0] * .pi / 180, dec = c.lines[s][p][1] * .pi / 180
                sx += cos(dec) * cos(ra); sy += cos(dec) * sin(ra); sz += sin(dec)
            }
        }
        let ra0 = atan2(sy, sx)
        let dec0 = atan2(sz, (sx * sx + sy * sy).squareRoot())

        // gnomonic projection onto a flat plane around the centre
        var result: [[CGPoint]] = []
        var maxExtent = 0.0
        for s in 0..<c.lines.count {
            var seg: [CGPoint] = []
            for p in 0..<c.lines[s].count {
                let ra = c.lines[s][p][0] * .pi / 180, dec = c.lines[s][p][1] * .pi / 180
                let cosc = sin(dec0) * sin(dec) + cos(dec0) * cos(dec) * cos(ra - ra0)
                let x = -(cos(dec) * sin(ra - ra0)) / cosc   // east is left when looking up
                let y = -(cos(dec0) * sin(dec) - sin(dec0) * cos(dec) * cos(ra - ra0)) / cosc
                seg.append(CGPoint(x: x, y: y))
                maxExtent = max(maxExtent, abs(x), abs(y))
            }
            result.append(seg)
        }
        guard maxExtent > 0 else { return result }
        for s in 0..<result.count {
            for p in 0..<result[s].count {
                result[s][p].x /= maxExtent
                result[s][p].y /= maxExtent
            }
        }
        return result
    }
}
