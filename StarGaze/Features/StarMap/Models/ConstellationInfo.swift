import Foundation

// Per-constellation text and art for the info sheet (Data/constellation-info.json).
// Names match the catalogue in constellations.json.

struct ConstellationInfo: Decodable {
    let name: String
    let description: String
    let astrologySymbol: String   // zodiac glyph, empty for non-zodiac constellations
    let image: String             // image path, empty until art is added
}

enum ConstellationInfoCatalog {
    static let byName: [String: ConstellationInfo] = {
        guard let url = Bundle.main.url(forResource: "constellation-info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ConstellationInfo].self, from: data) else {
            print("⚠️ constellation-info.json is missing from the app bundle")
            return [:]
        }
        return Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func info(for name: String) -> ConstellationInfo? { byName[name] }
}
