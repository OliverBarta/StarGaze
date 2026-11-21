import Foundation

// The bundled constellation catalogue (Data/constellations.json).
// Each constellation is a list of line segments; each point is [RA degrees, Dec degrees].

struct CatalogFile: Decodable {
    let constellations: [CatalogConstellation]
}

struct CatalogConstellation: Decodable, Identifiable {
    let id: String          // short code, e.g. "Ori"
    let name: String        // e.g. "Orion"
    let rank: Int           // 1 = most prominent
    let lines: [[[Double]]] // segments -> points -> [ra, dec]
}

enum SkyCatalog {
    static let constellations: [CatalogConstellation] = {
        guard let url = Bundle.main.url(forResource: "constellations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
            print("⚠️ constellations.json is missing from the app bundle")
            return []
        }
        return file.constellations
    }()
}
